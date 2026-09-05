import Foundation

/// schemaVersion 迁移与配置校验。
public enum ConfigurationMigration {
    public static let currentVersion = 1

    public enum MigrationError: Error, Equatable {
        case unsupportedVersion(Int)
    }

    /// 从原始数据解析出当前版本的 Configuration。
    /// 先读 schemaVersion，再逐版本迁移；未来升版本在此追加分支。
    public static func configuration(from data: Data) throws -> Configuration {
        let version = schemaVersion(in: data)
        switch version {
        case currentVersion:
            return try JSONDecoder().decode(Configuration.self, from: data)
        default:
            throw MigrationError.unsupportedVersion(version)
        }
    }

    static func schemaVersion(in data: Data) -> Int {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = object["schemaVersion"] as? Int
        else {
            return -1
        }
        return version
    }
}

/// 过滤明显损坏的 handler/rule，保证 RuleEngine 永远能构造安全配置、不因单条坏数据崩溃。
public enum ConfigurationSanitizer {
    public static func sanitized(_ config: Configuration) -> Configuration {
        var result = config
        result.handlers = config.handlers.compactMap { handler -> FileHandler? in
            guard !handler.contentTypeIdentifier.isEmpty, !handler.fallbackApplication.bundleIdentifier.isEmpty else {
                return nil
            }
            var safe = handler
            safe.rules = handler.rules.filter {
                !$0.folderPath.isEmpty && !$0.targetApplication.bundleIdentifier.isEmpty
            }
            return safe
        }
        return result
    }
}
