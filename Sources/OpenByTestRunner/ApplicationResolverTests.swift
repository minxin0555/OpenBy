import Foundation
import OpenBy
import UniformTypeIdentifiers

private final class FakeAppLocator: AppLocating {
    var urls: [String: URL] = [:]
    var candidates: [URL] = []

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        urls[bundleIdentifier]
    }

    func urlsForApplications(toOpen contentType: UTType) -> [URL] {
        candidates
    }
}

enum ApplicationResolverTests {
    static let ownBundleID = "com.example.OpenBy"
    static let pdfExpert = ApplicationReference(
        bundleIdentifier: "com.readdle.PDFExpert",
        lastKnownPath: "/Applications/PDF Expert.app",
        displayName: "PDF Expert"
    )

    fileprivate static func resolver(_ locator: FakeAppLocator, own: String? = ownBundleID, fileExists: @escaping (String) -> Bool = { _ in false }) -> ApplicationResolver {
        ApplicationResolver(locator: locator, ownBundleIdentifier: own, fileExists: fileExists)
    }

    static let cases: [MiniTest.Case] = [
        MiniTest.Case("Bundle ID → URL（经 locator）", {
            let locator = FakeAppLocator()
            locator.urls["com.readdle.PDFExpert"] = URL(fileURLWithPath: "/Applications/PDF Expert.app")
            let r = resolver(locator)
            let url = try expectNotNil(r.applicationURL(for: pdfExpert))
            try expectEqual(url.path, "/Applications/PDF Expert.app")
        }),

        MiniTest.Case("应用缺失 → nil", {
            let locator = FakeAppLocator()
            let r = resolver(locator)
            try expectNil(r.applicationURL(for: pdfExpert))
        }),

        MiniTest.Case("lastKnownPath 兜底（路径存在时）", {
            let locator = FakeAppLocator()
            let r = resolver(locator, fileExists: { _ in true })
            let url = try expectNotNil(r.applicationURL(for: pdfExpert))
            try expectEqual(url.path, "/Applications/PDF Expert.app")
        }),

        MiniTest.Case("lastKnownPath 失效（路径不存在）→ nil", {
            let locator = FakeAppLocator()
            let r = resolver(locator, fileExists: { _ in false })
            try expectNil(r.applicationURL(for: pdfExpert))
        }),

        MiniTest.Case("OpenBy 自身被排除（防递归）", {
            let locator = FakeAppLocator()
            let selfRef = ApplicationReference(bundleIdentifier: ownBundleID, lastKnownPath: "/Applications/OpenBy.app", displayName: "OpenBy")
            let r = resolver(locator, fileExists: { _ in true })
            try expectNil(r.applicationURL(for: selfRef))
        }),

        MiniTest.Case("installedApplications 过滤自身", {
            let locator = FakeAppLocator()
            locator.candidates = [
                URL(fileURLWithPath: "/Applications/Preview.app"),
                URL(fileURLWithPath: "/Applications/PDF Expert.app"),
            ]
            // 注意：过滤自身依赖 Bundle(url:).bundleIdentifier 读取真实 bundle；
            // 此处用 ownBundleID 传入 fake URL 的 bundle 无法读取，因此自身过滤通过
            // reference.bundleIdentifier == own 在 applicationURL(for:) 层保证。
            let r = resolver(locator)
            let apps = r.installedApplications(toOpen: .pdf)
            // 无真实 bundle 时 bundleIdentifier 为空串，不应过滤 Preview。
            try check(apps.contains { $0.lastKnownPath?.hasSuffix("Preview.app") == true })
        }),
    ]
}
