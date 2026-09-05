import Foundation
import OpenBy

/// 记录调用的 fake opener。注意：FileOpening 协议**只有**"显式指定应用"一个入口，
/// 从结构上杜绝"裸 open(urls)"——防递归铁律由协议形态保证（文档 4.4）。
private final class FakeFileOpening: FileOpening {
    var openCalls: [(urls: [URL], appURL: URL)] = []
    var result: Result<Void, Error> = .success(())

    func open(_ urls: [URL], withApplicationAt appURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        openCalls.append((urls, appURL))
        completion(result)
    }
}

/// 构造一个最小 .app bundle（含 CFBundleIdentifier 的 Info.plist），供防递归校验读取。
private func makeBundle(bundleID: String, in directory: URL) throws -> URL {
    let appURL = directory.appendingPathComponent("Test.app", isDirectory: true)
    let contents = appURL.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": bundleID,
        "CFBundleName": "Test",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return appURL
}

enum WorkspaceOpeningTests {
    static let cases: [MiniTest.Case] = [
        MiniTest.Case("显式转发：文件组 + 目标应用 URL 原样透传", {
            let fake = FakeFileOpening()
            let opening = WorkspaceOpening(opener: fake)
            let urls = [URL(fileURLWithPath: "/A/a.pdf"), URL(fileURLWithPath: "/A/b.pdf")]
            let target = URL(fileURLWithPath: "/Applications/PDF Expert.app")

            var captured: Result<Void, Error>?
            opening.open(urls, in: target, openByBundleID: nil) { captured = $0 }

            try expectEqual(fake.openCalls.count, 1)
            try expectEqual(fake.openCalls[0].urls.map(\.path), ["/A/a.pdf", "/A/b.pdf"])
            try expectEqual(fake.openCalls[0].appURL.path, target.path)
            try expectSuccess(try expectNotNil(captured))
        }),

        MiniTest.Case("目标应用是 OpenBy 自身 → 拒绝（防御性防递归）", {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("OpenBySelf-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let selfApp = try makeBundle(bundleID: "com.example.OpenBy", in: dir)

            let fake = FakeFileOpening()
            let opening = WorkspaceOpening(opener: fake)
            var captured: Result<Void, Error>?
            opening.open([URL(fileURLWithPath: "/A/a.pdf")], in: selfApp, openByBundleID: "com.example.OpenBy") { captured = $0 }

            try check(fake.openCalls.isEmpty, "不应调用底层 opener")
            guard case .failure(let error) = try expectNotNil(captured) else {
                try check(false, "应失败")
                return
            }
            try expectEqual(error as? RoutingError, .recursiveTarget(bundleIdentifier: "com.example.OpenBy"))
        }),

        MiniTest.Case("openByBundleID 为 nil（swift run 调试场景）时正常转发", {
            let fake = FakeFileOpening()
            let opening = WorkspaceOpening(opener: fake)
            var captured: Result<Void, Error>?
            opening.open([URL(fileURLWithPath: "/A/a.pdf")], in: URL(fileURLWithPath: "/Applications/Preview.app"), openByBundleID: nil) { captured = $0 }
            try expectEqual(fake.openCalls.count, 1)
            try expectSuccess(try expectNotNil(captured))
        }),
    ]
}
