import Foundation

/// 配置持久化：Codable + 临时文件原子替换 + `.bak` 备份 + 只读内存快照。
///
/// 对应文档 10.4：主文件损坏时只读备份并提醒，不自动覆盖原始证据；完全损坏时返回空安全配置。
public final class ConfigurationStore {
    public let fileURL: URL
    private let fileManager: FileManager
    private var cached: Configuration?
    /// 最近一次加载的提示（如"配置损坏已回退备份"），供诊断页展示。
    public private(set) var lastLoadNote: String?

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("OpenBy", isDirectory: true).appendingPathComponent("config.json")
    }

    /// 加载配置（含损坏回退）。路由热路径只读 `snapshot()`，不重复碰磁盘。
    public func load() -> Configuration {
        if !fileManager.fileExists(atPath: fileURL.path) {
            let empty = Configuration(schemaVersion: ConfigurationMigration.currentVersion, handlers: [])
            cached = empty
            return empty
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let config = try ConfigurationMigration.configuration(from: data)
            let sanitized = ConfigurationSanitizer.sanitized(config)
            cached = sanitized
            return sanitized
        } catch {
            if let backupData = backupData(),
               let backup = try? ConfigurationMigration.configuration(from: backupData) {
                lastLoadNote = "主配置损坏，已从备份加载"
                let sanitized = ConfigurationSanitizer.sanitized(backup)
                cached = sanitized
                return sanitized
            }
            lastLoadNote = "配置损坏且无可用备份，已使用空配置"
            let empty = Configuration(schemaVersion: ConfigurationMigration.currentVersion, handlers: [])
            cached = empty
            return empty
        }
    }

    /// 原子保存，替换前把当前文件备份为 `.bak`。
    public func save(_ configuration: Configuration) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: backupURL)
            try fileManager.copyItem(at: fileURL, to: backupURL)
        }

        let data = try JSONEncoder().encode(configuration)
        let tmp = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try fileManager.replaceItemAt(fileURL, withItemAt: tmp)
        cached = configuration
    }

    /// 路由热路径读取的内存快照。
    public func snapshot() -> Configuration {
        if let cached { return cached }
        return load()
    }

    private var backupURL: URL {
        fileURL.appendingPathExtension("bak")
    }

    private func backupData() -> Data? {
        guard fileManager.fileExists(atPath: backupURL.path) else { return nil }
        return try? Data(contentsOf: backupURL)
    }
}
