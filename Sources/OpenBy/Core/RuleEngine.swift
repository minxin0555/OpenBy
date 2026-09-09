import Foundation
import UniformTypeIdentifiers

/// 不可变配置快照；规则预编译，类型匹配结果按扩展名缓存。
/// 缓存有锁且有容量/有效期限制，快照可安全地交给后台路由队列。
public struct RuleEngine {
    public let configuration: Configuration
    private struct CompiledHandler {
        let handler: FileHandler
        let type: UTType?
        let extensions: Set<String>
        let rules: [(rule: FolderRule, components: [String])]
    }
    private final class TypeCache {
        let lock = NSLock()
        var indices: [String: Int] = [:]
        var expiresAt = ProcessInfo.processInfo.systemUptime + 300
    }
    private let handlers: [CompiledHandler]
    private let cache = TypeCache()

    public init(configuration: Configuration) {
        self.configuration = configuration
        handlers = configuration.handlers.filter(\.enabled).map { handler in
            let type = UTType(handler.contentTypeIdentifier)
            return CompiledHandler(
                handler: handler,
                type: type,
                extensions: Set((handler.displayExtensions + (type?.tags[.filenameExtension] ?? [])).map { $0.lowercased() }),
                rules: handler.rules.filter(\.enabled).map { ($0, PathMatcher.normalizedComponents(of: $0.folderPath)) }
            )
        }
    }

    public func resolveDecision(for fileURL: URL) -> RoutingDecision {
        guard fileURL.isFileURL, let index = matchingHandlerIndex(for: fileURL) else { return .none }
        let compiled = handlers[index]
        let components = PathMatcher.normalizedComponents(of: fileURL.path)
        for (rule, folder) in compiled.rules {
            if PathMatcher.isPath(components, insideFolder: folder, includesDescendants: rule.includesDescendants) {
                return .rule(rule.targetApplication)
            }
        }
        return .fallback(compiled.handler.fallbackApplication)
    }

    public func fallbackApplication(for fileURL: URL) -> ApplicationReference? {
        guard fileURL.isFileURL, let index = matchingHandlerIndex(for: fileURL) else { return nil }
        return handlers[index].handler.fallbackApplication
    }

    private func matchingHandlerIndex(for fileURL: URL) -> Int? {
        let ext = fileURL.pathExtension.lowercased()
        cache.lock.lock()
        if ProcessInfo.processInfo.systemUptime >= cache.expiresAt {
            cache.indices.removeAll(keepingCapacity: true)
            cache.expiresAt = ProcessInfo.processInfo.systemUptime + 300
        }
        let cached = cache.indices[ext]
        cache.lock.unlock()
        if let cached { return cached < 0 ? nil : cached }

        // 必须按原有 handler 优先级求完整匹配，不能让扩展名捷径越过通用类型。
        let fileType = UTType(filenameExtension: ext)
        let index = handlers.firstIndex { compiled in
            if compiled.handler.groupName != nil {
                return compiled.handler.displayExtensions.contains { $0.lowercased() == ext }
            }
            if let fileType {
                if fileType.identifier == compiled.handler.contentTypeIdentifier { return true }
                if let type = compiled.type,
                   fileType.conforms(to: type) || type.conforms(to: fileType) { return true }
            }
            return compiled.extensions.contains(ext)
        }
        cache.lock.lock()
        if cache.indices.count >= 256 { cache.indices.removeAll(keepingCapacity: true) }
        cache.indices[ext] = index ?? -1
        cache.lock.unlock()
        return index
    }
}

/// 多文件请求按目标应用分组，每个目标只转发一次（对应文档第 7 节第 8 步）。
public enum BatchRouter {
    /// 分组结果：每个目标应用对应一组文件；`unrouted` 是无法路由的文件。
    public struct Result {
        public let groups: [(target: ApplicationReference, urls: [URL])]
        public let unrouted: [URL]
    }

    public static func group(_ fileURLs: [URL], engine: RuleEngine) -> Result {
        var grouped: [ApplicationReference: [URL]] = [:]
        var unrouted: [URL] = []

        for url in fileURLs {
            switch engine.resolveDecision(for: url) {
            case .rule(let app), .fallback(let app):
                grouped[app, default: []].append(url)
            case .none:
                unrouted.append(url)
            }
        }

        return Result(
            groups: grouped.map { (target: $0.key, urls: $0.value) },
            unrouted: unrouted
        )
    }
}
