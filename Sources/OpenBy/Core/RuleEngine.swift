import Foundation
import UniformTypeIdentifiers

/// 纯函数式路由引擎：注入不可变 Configuration 快照，对文件 URL 输出路由决策。
/// 不做任何文件系统、NSWorkspace 或网络 I/O。
///
/// 性能：目录组件在 init 预计算（文档第 9 节），文件路径每个文件只标准化一次；
/// 规则循环是纯数组前缀比较，1,000 条规则单文件匹配 < 1ms。
public struct RuleEngine {
    public let configuration: Configuration
    /// 规则 id → 标准化目录组件（路由热路径不复算）。
    private let normalizedFolderComponents: [UUID: [String]]

    public init(configuration: Configuration) {
        self.configuration = configuration
        var map: [UUID: [String]] = [:]
        for handler in configuration.handlers {
            for rule in handler.rules {
                map[rule.id] = PathMatcher.normalizedComponents(of: rule.folderPath)
            }
        }
        self.normalizedFolderComponents = map
    }

    /// 对单个文件求路由决策。
    public func resolveDecision(for fileURL: URL) -> RoutingDecision {
        guard fileURL.isFileURL else { return .none }
        guard let handler = matchingHandler(for: fileURL) else { return .none }

        // 文件路径只标准化一次。
        let fileComponents = PathMatcher.normalizedComponents(of: fileURL.path)

        // 规则从上到下，第一条命中即停止（first-match-wins）。
        for rule in handler.rules where rule.enabled {
            guard let folderComponents = normalizedFolderComponents[rule.id] else { continue }
            if PathMatcher.isPath(fileComponents, insideFolder: folderComponents, includesDescendants: rule.includesDescendants) {
                return .rule(rule.targetApplication)
            }
        }
        return .fallback(handler.fallbackApplication)
    }

    /// 找第一个启用的、能处理该文件的 handler。
    private func matchingHandler(for fileURL: URL) -> FileHandler? {
        let fileExtension = fileURL.pathExtension
        let fileType = UTType(filenameExtension: fileExtension)

        for handler in configuration.handlers where handler.enabled {
            if handlerMatches(handler, fileExtension: fileExtension, fileType: fileType) {
                return handler
            }
        }
        return nil
    }

    /// 该文件所属 handler 的回退应用（用于"规则目标缺失时降级到 fallback"）。
    public func fallbackApplication(for fileURL: URL) -> ApplicationReference? {
        matchingHandler(for: fileURL)?.fallbackApplication
    }

    private func handlerMatches(_ handler: FileHandler, fileExtension: String, fileType: UTType?) -> Bool {
        let handlerType = UTType(handler.contentTypeIdentifier)

        if let fileType {
            // 文件类型等于 handler 类型，或存在继承关系（任意方向）。
            if fileType.identifier == handler.contentTypeIdentifier { return true }
            if let handlerType {
                if fileType.conforms(to: handlerType) { return true }
                if handlerType.conforms(to: fileType) { return true }
            }
        }
        // 扩展名兜底匹配（大小写不敏感）。
        return handler.displayExtensions.contains(where: { $0.lowercased() == fileExtension.lowercased() })
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
