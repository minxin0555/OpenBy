import Foundation
import OpenBy

enum ConfigurationMigrationTests {
    static let cases: [MiniTest.Case] = [
        MiniTest.Case("当前版本可解码", {
            let config = Configuration(schemaVersion: 1, handlers: [
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
