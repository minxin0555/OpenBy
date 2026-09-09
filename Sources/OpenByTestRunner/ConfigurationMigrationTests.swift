import Foundation
import OpenBy

enum ConfigurationMigrationTests {
    static let cases: [MiniTest.Case] = [
        MiniTest.Case("当前版本可解码", {
            let config = Configuration(schemaVersion: ConfigurationMigration.currentVersion, handlers: [
                FileHandler(
                    contentTypeIdentifier: "com.adobe.pdf",
                    fallbackApplication: ApplicationReference(bundleIdentifier: "com.apple.Preview", displayName: "Preview"),
                    displayExtensions: ["pdf"]
                ),
            ])
            let data = try JSONEncoder().encode(config)
            let decoded = try ConfigurationMigration.configuration(from: data)
            try expectEqual(decoded, config)
        }),

        MiniTest.Case("旧配置迁移后仍保持单类型规则和原默认应用", {
            let original = ApplicationReference(bundleIdentifier: "original.app", displayName: "Original")
            let handler = FileHandler(contentTypeIdentifier: "public.png", fallbackApplication: original,
                                      displayExtensions: ["png"], previousDefaultApplication: original)
            let old = Configuration(schemaVersion: 1, handlers: [handler])
            let data = try JSONEncoder().encode(old)
            let migrated = try ConfigurationMigration.configuration(from: data)
            try expectEqual(migrated.schemaVersion, ConfigurationMigration.currentVersion)
            try expectEqual(migrated.handlers, [handler])
            try expectNil(migrated.handlers[0].groupName)
        }),

        MiniTest.Case("格式组名称、后缀与每种格式的恢复记录可持久化", {
            let app = ApplicationReference(bundleIdentifier: "original.app", displayName: "Original")
            let group = FileHandler(contentTypeIdentifier: "public.jpeg", fallbackApplication: app,
                                    displayExtensions: ["jpg", "webp"], groupName: "我的图片",
                                    previousDefaultApplications: ["public.jpeg": app, "org.webmproject.webp": app])
            let config = Configuration(schemaVersion: ConfigurationMigration.currentVersion, handlers: [group])
            let decoded = try ConfigurationMigration.configuration(from: JSONEncoder().encode(config))
            try expectEqual(decoded, config)
        }),

        MiniTest.Case("尚未选择应用的格式组在重载时保留", {
            let group = FileHandler(contentTypeIdentifier: "public.jpeg",
                fallbackApplication: ApplicationReference(bundleIdentifier: "", displayName: "未指定"),
                displayExtensions: ["jpg", "webp"], groupName: "图片")
            let config = Configuration(schemaVersion: ConfigurationMigration.currentVersion, handlers: [group])
            try expectEqual(ConfigurationSanitizer.sanitized(config).handlers, [group])
        }),

        MiniTest.Case("未知 schemaVersion 抛错", {
            let json = #"{"schemaVersion": 99, "handlers": []}"#
            try expectThrows({ try ConfigurationMigration.configuration(from: Data(json.utf8)) })
        }),

        MiniTest.Case("schemaVersion 缺失按损坏处理", {
            let json = #"{"handlers": []}"#
            try expectThrows({ try ConfigurationMigration.configuration(from: Data(json.utf8)) })
        }),

        // MARK: 校验过滤
        MiniTest.Case("坏 handler（无 bundle id 的 fallback）被过滤", {
            let bad = FileHandler(
                contentTypeIdentifier: "com.example.bad",
                fallbackApplication: ApplicationReference(bundleIdentifier: "", displayName: "")
            )
            let good = FileHandler(
                contentTypeIdentifier: "com.adobe.pdf",
                fallbackApplication: ApplicationReference(bundleIdentifier: "com.apple.Preview", displayName: "Preview")
            )
            let config = Configuration(schemaVersion: 1, handlers: [bad, good])
            let sanitized = ConfigurationSanitizer.sanitized(config)
            try expectEqual(sanitized.handlers.count, 1)
            try expectEqual(sanitized.handlers[0].contentTypeIdentifier, "com.adobe.pdf")
        }),

        MiniTest.Case("坏规则（空目录）被过滤，handler 保留", {
            let handler = FileHandler(
                contentTypeIdentifier: "com.adobe.pdf",
                fallbackApplication: ApplicationReference(bundleIdentifier: "com.apple.Preview", displayName: "Preview"),
                rules: [
                    FolderRule(folderPath: "", includesDescendants: true,
                               targetApplication: ApplicationReference(bundleIdentifier: "com.readdle.PDFExpert", displayName: "PDF Expert")),
                    FolderRule(folderPath: "/Users/t/文献", includesDescendants: true,
                               targetApplication: ApplicationReference(bundleIdentifier: "com.readdle.PDFExpert", displayName: "PDF Expert")),
                ]
            )
            let sanitized = ConfigurationSanitizer.sanitized(Configuration(schemaVersion: 1, handlers: [handler]))
            try expectEqual(sanitized.handlers[0].rules.count, 1)
            try expectEqual(sanitized.handlers[0].rules[0].folderPath, "/Users/t/文献")
        }),
    ]
}
