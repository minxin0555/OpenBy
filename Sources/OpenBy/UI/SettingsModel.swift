import AppKit
import UniformTypeIdentifiers

/// 设置界面共享模型：持有当前配置，提供文件类型 / 规则 / 接管恢复的修改操作，
/// 每次变更落盘并通知协调器热更新。
@MainActor
final class SettingsModel {
    static func typeDisplayName(_ handler: FileHandler) -> String {
        if let name = handler.groupName { return name }
        switch handler.displayExtensions.first?.lowercased() {
        case "pdf": return "PDF 文档"
        case "md", "markdown": return "Markdown"
        case "txt": return "文本文件"
        default: return (handler.displayExtensions.first?.uppercased() ?? "未知类型") + " 文件"
        }
    }

    let store: ConfigurationStore
    let resolver: ApplicationResolver
    let associationService: AssociationService
    let openByBundleID: String?
    var onConfigurationChanged: (() -> Void)?

    private(set) var configuration: Configuration

    init(
        store: ConfigurationStore,
        resolver: ApplicationResolver,
        associationService: AssociationService,
        openByBundleID: String?,
        onConfigurationChanged: (() -> Void)?
    ) {
        self.store = store
        self.resolver = resolver
        self.associationService = associationService
        self.openByBundleID = openByBundleID
        self.onConfigurationChanged = onConfigurationChanged
        self.configuration = store.snapshot()
    }

    // MARK: - 持久化

    private func save(update: (inout Configuration) -> Void) {
        update(&configuration)
        do {
            try store.save(configuration)
        } catch {
            NSSound.beep()
        }
        onConfigurationChanged?()
    }

    // MARK: - 文件类型（handler）

    /// 添加扩展名。返回新建 handler，或 nil（解析失败 / 重复）。
    @discardableResult
    func addHandler(extension ext: String) -> FileHandler? {
        guard let ext = Self.normalizedExtension(ext) else { return nil }
        guard let type = UTType(filenameExtension: ext) else { return nil }

        guard conflictingHandler(extensions: [ext]) == nil else { return nil }

        // fallback = 当前该类型默认应用（通常是接管前的"预览"等）。
        let fallback = associationService.previousDefaultApplication(for: type, unlessBundleID: openByBundleID ?? "")
            ?? ApplicationReference(bundleIdentifier: "", displayName: "未指定")

        let handler = FileHandler(contentTypeIdentifier: type.identifier, fallbackApplication: fallback, displayExtensions: [ext])
        save { $0.handlers.append(handler) }
        return handler
    }

    static func normalizedExtension(_ input: String) -> String? {
        FormatGroups.normalizedExtension(input)
    }

    func conflictingHandler(extensions: [String], excluding id: UUID? = nil) -> FileHandler? {
        let identifiers = Set(extensions.compactMap { UTType(filenameExtension: $0)?.identifier })
        return configuration.handlers.first { handler in
            handler.id != id && (
                !Set(handler.displayExtensions).isDisjoint(with: extensions) ||
                handler.contentTypes.contains { identifiers.contains($0.identifier) }
            )
        }
    }

    func saveGroup(name: String, extensions: [String], editing id: UUID?) throws -> FileHandler {
        guard let first = extensions.first, let type = UTType(filenameExtension: first) else {
            throw NSError(domain: "OpenBy", code: 2, userInfo: [NSLocalizedDescriptionKey: "没有可用的文件格式。"])
        }
        var group: FileHandler
        if let id, let existing = handler(id: id) {
            group = existing
            if group.previousDefaultApplications == nil { group.previousDefaultApplications = [:] }
            if let previous = group.previousDefaultApplication {
                group.previousDefaultApplications?[group.contentTypeIdentifier] = previous
            }
        } else {
            let fallback = associationService.previousDefaultApplication(for: type, unlessBundleID: openByBundleID ?? "")
                ?? ApplicationReference(bundleIdentifier: "", displayName: "未指定")
            group = FileHandler(contentTypeIdentifier: type.identifier, fallbackApplication: fallback)
        }
        group.groupName = name
        group.displayExtensions = extensions
        group.contentTypeIdentifier = type.identifier
        group.previousDefaultApplication = nil
        let retainedTypes = Set(group.contentTypes.map(\.identifier))
        group.previousDefaultApplications = group.previousDefaultApplications?.filter { retainedTypes.contains($0.key) }
        var updated = configuration
        if let index = updated.handlers.firstIndex(where: { $0.id == group.id }) {
            updated.handlers[index] = group
        } else { updated.handlers.append(group) }
        try store.save(updated)
        configuration = updated
        onConfigurationChanged?()
        return group
    }

    func removeHandler(id: UUID) {
        save { $0.handlers.removeAll { $0.id == id } }
    }

    func updateHandler(id: UUID, update: (inout FileHandler) -> Void) {
        save { config in
            if let index = config.handlers.firstIndex(where: { $0.id == id }) {
                update(&config.handlers[index])
            }
        }
    }

    // MARK: - 接管 / 恢复

    func managedCount(_ handler: FileHandler) -> Int {
        handler.contentTypes.filter {
            associationService.isManagedByOpenBy(contentType: $0, openByBundleID: openByBundleID ?? "")
        }.count
    }

    func isManaged(handler: FileHandler, contentType: UTType) -> Bool {
        !handler.contentTypes.isEmpty && managedCount(handler) == handler.contentTypes.count
    }

    private func originalApplications(_ handler: FileHandler) -> [String: ApplicationReference] {
        var originals = handler.previousDefaultApplications ?? [:]
        if let previous = handler.previousDefaultApplication, originals[handler.contentTypeIdentifier] == nil {
            originals[handler.contentTypeIdentifier] = previous
        }
        return originals
    }

    /// 先持久化每种格式的恢复记录，再申请系统关联。
    func takeOver(handlerID: UUID, contentType: UTType, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let ownBundleID = openByBundleID, let handler = handler(id: handlerID) else {
            completion(.failure(RoutingError.recursiveTarget(bundleIdentifier: "OpenBy")))
            return
        }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            completion(.failure(NSError(domain: "OpenBy", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "请从 .app 包中运行应用后再启用自动打开"])))
            return
        }
        var originals = originalApplications(handler)
        for type in handler.contentTypes {
            if let previous = associationService.previousDefaultApplication(for: type, unlessBundleID: ownBundleID) {
                originals[type.identifier] = previous
            }
        }
        var updated = configuration
        guard let index = updated.handlers.firstIndex(where: { $0.id == handlerID }) else { return }
        updated.handlers[index].previousDefaultApplications = originals
        do {
            try store.save(updated)
            configuration = updated
            onConfigurationChanged?()
        } catch { completion(.failure(error)); return }
        associationService.takeOverGroup(contentTypes: handler.contentTypes, targetAppURL: Bundle.main.bundleURL,
                                         openByBundleID: ownBundleID, completion: completion)
    }

    func restoreDefault(handlerID: UUID, contentType: UTType, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let handler = handler(id: handlerID) else { completion(.success(false)); return }
        restoreTypes(handler: handler, types: handler.contentTypes, completion: completion)
    }

    func restoreTypes(handler: FileHandler, types: [UTType], completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let ownBundleID = openByBundleID else { completion(.success(false)); return }
        associationService.restoreGroup(contentTypes: types, previous: originalApplications(handler),
                                        openByBundleID: ownBundleID, completion: completion)
    }

    // MARK: - 规则

    @discardableResult
    func addRule(to handlerID: UUID, folderPath: String, includesDescendants: Bool, target: ApplicationReference) -> Bool {
        let expanded = PathInput.expandedAbsolutePath(folderPath)
        guard !expanded.isEmpty else { return false }
        var created = false
        save { config in
            if let index = config.handlers.firstIndex(where: { $0.id == handlerID }) {
                config.handlers[index].rules.append(
                    FolderRule(folderPath: expanded, includesDescendants: includesDescendants, targetApplication: target)
                )
                created = true
            }
        }
        return created
    }

    func updateRule(handlerID: UUID, ruleID: UUID, update: (inout FolderRule) -> Void) {
        save { config in
            guard let index = config.handlers.firstIndex(where: { $0.id == handlerID }) else { return }
            if let ruleIndex = config.handlers[index].rules.firstIndex(where: { $0.id == ruleID }) {
                update(&config.handlers[index].rules[ruleIndex])
            }
        }
    }

    func removeRule(handlerID: UUID, ruleID: UUID) {
        save { config in
            guard let index = config.handlers.firstIndex(where: { $0.id == handlerID }) else { return }
            config.handlers[index].rules.removeAll { $0.id == ruleID }
        }
    }

    /// 拖动排序：把 source 位置的规则移到 destination 位置。
    func moveRule(handlerID: UUID, from source: Int, to destination: Int) {
        save { config in
            guard let index = config.handlers.firstIndex(where: { $0.id == handlerID }) else { return }
            var rules = config.handlers[index].rules
            guard rules.indices.contains(source) else { return }
            let rule = rules.remove(at: source)
            let dest = min(max(destination, 0), rules.count)
            rules.insert(rule, at: dest)
            config.handlers[index].rules = rules
        }
    }

    func handler(id: UUID) -> FileHandler? {
        configuration.handlers.first { $0.id == id }
    }

    static func applicationReference(from url: URL) -> ApplicationReference {
        ApplicationReference(
            bundleIdentifier: Bundle(url: url)?.bundleIdentifier ?? "",
            lastKnownPath: url.path,
            displayName: url.deletingPathExtension().lastPathComponent
        )
    }
}
