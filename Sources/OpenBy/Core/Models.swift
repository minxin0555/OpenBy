import Foundation
import UniformTypeIdentifiers

/// 顶层配置。schemaVersion 用于未来迁移；handler 顺序即优先级。
public struct Configuration: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var handlers: [FileHandler]

    public init(schemaVersion: Int, handlers: [FileHandler]) {
        self.schemaVersion = schemaVersion
        self.handlers = handlers
    }
}

/// 一个文件类型的处理器：描述该类型、回退应用、接管前的默认应用，以及有序的文件夹规则。
public struct FileHandler: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// 系统身份（UTI），例如 `com.adobe.pdf`。
    public var contentTypeIdentifier: String
    /// 用户展示与初始解析用的扩展名，例如 `["pdf"]`。
    public var displayExtensions: [String]
    /// 非 nil 表示显式格式组，路由只匹配组中列出的后缀。
    public var groupName: String?
    /// 每种系统文件类型分别保留原应用，整组停用时逐一恢复。
    public var previousDefaultApplications: [String: ApplicationReference]?
    public var enabled: Bool
    /// 未命中任何规则时使用的应用。
    public var fallbackApplication: ApplicationReference
    /// 接管前记录的原默认应用；仅当"当前默认仍是 OpenBy"时才用它恢复。
    public var previousDefaultApplication: ApplicationReference?
    /// 规则从上到下匹配，第一条命中即生效（first-match-wins）。
    public var rules: [FolderRule]

    public init(
        contentTypeIdentifier: String,
        fallbackApplication: ApplicationReference,
        displayExtensions: [String] = [],
        enabled: Bool = true,
        previousDefaultApplication: ApplicationReference? = nil,
        rules: [FolderRule] = [],
        id: UUID = UUID(),
        groupName: String? = nil,
        previousDefaultApplications: [String: ApplicationReference]? = nil
    ) {
        self.id = id
        self.contentTypeIdentifier = contentTypeIdentifier
        self.displayExtensions = displayExtensions
        self.enabled = enabled
        self.fallbackApplication = fallbackApplication
        self.previousDefaultApplication = previousDefaultApplication
        self.rules = rules
        self.groupName = groupName
        self.previousDefaultApplications = previousDefaultApplications
    }

    public var contentTypes: [UTType] {
        guard groupName != nil else { return UTType(contentTypeIdentifier).map { [$0] } ?? [] }
        var seen = Set<String>()
        return displayExtensions.compactMap { UTType(filenameExtension: $0) }
            .filter { seen.insert($0.identifier).inserted }
    }
}

/// 预设只填充可编辑草稿；保存后以用户确认的后缀为准。
public enum FormatGroups {
    public static let presets: [(name: String, extensions: [String])] = [
        ("常见图片", ["jpg", "jpeg", "png", "gif", "webp", "heic", "bmp", "tif", "tiff", "svg"]),
        ("常见视频", ["mp4", "mov", "mkv", "avi", "m4v", "webm"]),
        ("常见音频", ["mp3", "m4a", "wav", "flac", "aac", "aiff", "ogg"]),
        ("常见文档", ["pdf", "txt", "md", "rtf", "doc", "docx", "xls", "xlsx", "ppt", "pptx"]),
    ]

    public static func normalizedExtension(_ input: String) -> String? {
        var ext = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ext.hasPrefix(".") { ext.removeFirst() }
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
            .union(CharacterSet(charactersIn: ". /\\:*?\"<>|,;，；"))
        guard !ext.isEmpty, ext.rangeOfCharacter(from: forbidden) == nil else { return nil }
        return ext
    }

    public static func parseExtensions(_ input: String) -> [String]? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;，；"))
        let parts = input.components(separatedBy: separators).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        var seen = Set<String>()
        var result: [String] = []
        for part in parts {
            guard let ext = normalizedExtension(part) else { return nil }
            if seen.insert(ext).inserted { result.append(ext) }
        }
        return result
    }
}

/// 一条"某文件夹内 → 目标应用"规则。顺序持久化，不可排序去重。
public struct FolderRule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var enabled: Bool
    /// 绝对路径；不做符号链接解析。
    public var folderPath: String
    /// true = 任意深度子项；false = 仅直接子文件。
    public var includesDescendants: Bool
    public var targetApplication: ApplicationReference

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        folderPath: String,
        includesDescendants: Bool,
        targetApplication: ApplicationReference
    ) {
        self.id = id
        self.enabled = enabled
        self.folderPath = folderPath
        self.includesDescendants = includesDescendants
        self.targetApplication = targetApplication
    }
}

/// 应用引用。Bundle ID 是身份；lastKnownPath 只是缓存/后备。
/// Hashable 用于按目标应用分组（BatchRouter 的字典键）。
public struct ApplicationReference: Codable, Equatable, Hashable, Sendable {
    public var bundleIdentifier: String
    public var lastKnownPath: String?
    public var displayName: String

    public init(bundleIdentifier: String, lastKnownPath: String? = nil, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.lastKnownPath = lastKnownPath
        self.displayName = displayName
    }
}

/// 路由决策结果。
public enum RoutingDecision: Equatable, Sendable {
    /// 命中某条文件夹规则。
    case rule(ApplicationReference)
    /// 未命中规则，回退到默认应用。
    case fallback(ApplicationReference)
    /// 找不到对应的启用 handler。
    case none
}

/// 路由过程中的错误。
public enum RoutingError: Error, Equatable {
    /// 目标应用缺失，且 fallback 也缺失。
    case noUsableApplication(bundleIdentifier: String)
    /// 目标是 OpenBy 自身（配置错误，防御性拦截）。
    case recursiveTarget(bundleIdentifier: String)
    /// 不是本地 file URL。
    case notAFileURL
    /// 没有与该文件匹配的启用处理器。
    case noMatchingHandler
}
