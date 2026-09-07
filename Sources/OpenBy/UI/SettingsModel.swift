import AppKit
import UniformTypeIdentifiers

/// 设置界面共享模型：持有当前配置，提供文件类型 / 规则 / 接管恢复的修改操作，
/// 每次变更落盘并通知协调器热更新。
@MainActor
final class SettingsModel {
    let store: ConfigurationStore
    let resolver: ApplicationResolver
    let associationService: AssociationService
    let openByBundleID: String?
    var onConfigurationChanged: (() -> Void)?
    var startupMilliseconds: Double = 0
    var diagnosticsProvider: (@escaping ([String], [RoutingMeasurement]) -> Void) -> Void = { $0([], []) }

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
        let ext = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !ext.isEmpty, !ext.contains(".") else { return nil }
        guard let type = UTType(filenameExtension: ext) else { return nil }

        let duplicates = configuration.handlers.contains {
            $0.contentTypeIdentifier == type.identifier || $0.displayExtensions.contains(ext)
        }
        guard !duplicates else { return nil }

        // fallback = 当前该类型默认应用（通常是接管前的"预览"等）。
        let fallback = associationService.previousDefaultApplication(for: type, unlessBundleID: openByBundleID ?? "")
            ?? ApplicationReference(bundleIdentifier: "", displayName: "未指定")

        let handler = FileHandler(contentTypeIdentifier: type.identifier, fallbackApplication: fallback, displayExtensions: [ext])
        save { $0.handlers.append(handler) }
        return handler
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

    /// 设为默认：先记录接管前默认，再异步接管并验证。
    func takeOver(handlerID: UUID, contentType: UTType, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let ownBundleID = openByBundleID else {
            completion(.failure(RoutingError.recursiveTarget(bundleIdentifier: "OpenBy")))
            return
        }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            completion(.failure(NSError(
                domain: "OpenBy", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "请从 .app 包中运行应用后再接管默认关联"]
            )))
            return
        }
        // 记录接管前默认（仅当尚未记录，避免覆盖）。
        if let previous = associationService.previousDefaultApplication(for: contentType, unlessBundleID: ownBundleID) {
            updateHandler(id: handlerID) { handler in
                if handler.previousDefaultApplication == nil {
                    handler.previousDefaultApplication = previous
                }
            }
        }
        associationService.takeOver(
            contentType: contentType,
            targetAppURL: Bundle.main.bundleURL,
            openByBundleID: ownBundleID
        ) { result in
            completion(result)
        }
    }

    /// 停止接管：仅当当前默认仍是 OpenBy 时恢复接管前默认。
    func restoreDefault(handlerID: UUID, contentType: UTType, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let previous = handler(id: handlerID)?.previousDefaultApplication,
              let ownBundleID = openByBundleID else {
            completion(.success(false))
            return
        }
        associationService.restorePreviousDefault(
            contentType: contentType,
            previous: previous,
            openByBundleID: ownBundleID
        ) { result in
            completion(result)
        }
    }

    func isManaged(handler: FileHandler, contentType: UTType) -> Bool {
        associationService.isManagedByOpenBy(contentType: contentType, openByBundleID: openByBundleID ?? "")
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

    // MARK: - 试测（不真正打开）

    func describeRouting(for url: URL) -> String {
        let engine = RuleEngine(configuration: configuration)
        switch engine.resolveDecision(for: url) {
        case .rule(let app):
            return "命中规则 → \(app.displayName)（\(app.bundleIdentifier)）"
        case .fallback(let app):
            return "默认回退 → \(app.displayName)（\(app.bundleIdentifier)）"
        case .none:
            return "无匹配的处理器"
        }
    }

    static func applicationReference(from url: URL) -> ApplicationReference {
        ApplicationReference(
            bundleIdentifier: Bundle(url: url)?.bundleIdentifier ?? "",
            lastKnownPath: url.path,
            displayName: url.deletingPathExtension().lastPathComponent
        )
    }
}
