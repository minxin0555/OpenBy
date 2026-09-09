import Foundation
import OpenBy

enum ConfigurationStoreTests {
    static func makeTempConfigURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenByTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func sampleConfiguration() -> Configuration {
        Configuration(schemaVersion: ConfigurationMigration.currentVersion, handlers: [
            FileHandler(
                contentTypeIdentifier: "com.adobe.pdf",
                fallbackApplication: ApplicationReference(bundleIdentifier: "com.apple.Preview", displayName: "Preview"),
                displayExtensions: ["pdf"],
                rules: [
                    FolderRule(
                        folderPath: "/Users/t/文献",
                        includesDescendants: true,
                        targetApplication: ApplicationReference(bundleIdentifier: "com.readdle.PDFExpert", displayName: "PDF Expert")
                    ),
                ]
            ),
        ])
    }

    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static let cases: [MiniTest.Case] = [
        MiniTest.Case("保存→加载往返一致", {
            let url = makeTempConfigURL()
            let store = ConfigurationStore(fileURL: url)
            let sample = sampleConfiguration()
            try store.save(sample)
            let loaded = store.load()
            try expectEqual(loaded, sample)
            cleanup(url)
        }),

        MiniTest.Case("保存后无 .tmp 残留", {
            let url = makeTempConfigURL()
            let store = ConfigurationStore(fileURL: url)
            try store.save(sampleConfiguration())
            let tmpExists = FileManager.default.fileExists(atPath: url.appendingPathExtension("tmp").path)
            try check(!tmpExists, "应无 .tmp 残留")
            cleanup(url)
        }),

        MiniTest.Case("主文件损坏 + .bak 存在 → 从备份加载", {
            let url = makeTempConfigURL()
            let store = ConfigurationStore(fileURL: url)
            let sample = sampleConfiguration()
            try store.save(sample)
            try store.save(sample) // 第二次保存会产生 .bak
            try Data("corrupted".utf8).write(to: url) // 损坏主文件
            let loaded = store.load()
            try expectEqual(loaded, sample)
            try check(store.lastLoadNote != nil, "应记录加载提示")
            cleanup(url)
        }),

        MiniTest.Case("主文件与备份均损坏 → 空安全配置", {
            let url = makeTempConfigURL()
            let store = ConfigurationStore(fileURL: url)
            try store.save(sampleConfiguration())
            try store.save(sampleConfiguration())
            try Data("corrupted".utf8).write(to: url)
            try Data("also corrupted".utf8).write(to: url.appendingPathExtension("bak"))
            let loaded = store.load()
            try expectEqual(loaded, Configuration(schemaVersion: ConfigurationMigration.currentVersion, handlers: []))
            cleanup(url)
        }),

        MiniTest.Case("文件不存在 → 空安全配置", {
            let url = makeTempConfigURL()
            let store = ConfigurationStore(fileURL: url)
            let loaded = store.load()
            try expectEqual(loaded, Configuration(schemaVersion: ConfigurationMigration.currentVersion, handlers: []))
            cleanup(url)
        }),
    ]
}
