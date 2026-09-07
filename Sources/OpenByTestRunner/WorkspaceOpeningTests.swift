import Foundation
import OpenBy
import UniformTypeIdentifiers

/// 记录调用的 fake opener。注意：FileOpening 协议**只有**"显式指定应用"一个入口，
/// 从结构上杜绝"裸 open(urls)"——防递归铁律由协议形态保证（文档 4.4）。
private final class FakeFileOpening: FileOpening {
    private let lock = NSLock()
    private var calls: [(urls: [URL], appURL: URL)] = []
    private var callbacks: [(Result<Void, Error>) -> Void] = []
    var completesImmediately = true
    var openCalls: [(urls: [URL], appURL: URL)] {
        lock.lock(); defer { lock.unlock() }; return calls
    }
    func open(_ urls: [URL], withApplicationAt appURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        calls.append((urls, appURL))
        callbacks.append(completion)
        lock.unlock()
        if completesImmediately { completion(.success(())) }
    }
    func complete(_ index: Int, result: Result<Void, Error> = .success(())) {
        lock.lock()
        let callback = callbacks[index]
        lock.unlock()
        callback(result)
    }
}

private final class CoordinatorAppLocator: AppLocating {
    let applications: [String: URL]

    init(applications: [String: URL]) {
        self.applications = applications
    }

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        applications[bundleIdentifier]
    }

    func urlsForApplications(toOpen contentType: UTType) -> [URL] {
        []
    }
}

private let coordinatorAppA = ApplicationReference(bundleIdentifier: "com.example.AppA", displayName: "AppA")
private let coordinatorAppB = ApplicationReference(bundleIdentifier: "com.example.AppB", displayName: "AppB")
private let coordinatorFallback = ApplicationReference(bundleIdentifier: "com.example.Fallback", displayName: "Fallback")

private func coordinatorConfiguration(fallback: ApplicationReference = coordinatorFallback) -> Configuration {
    Configuration(schemaVersion: 1, handlers: [
        FileHandler(contentTypeIdentifier: UTType.pdf.identifier, fallbackApplication: fallback,
                    displayExtensions: ["pdf"], rules: [
                        FolderRule(folderPath: "/AppA", includesDescendants: true, targetApplication: coordinatorAppA),
                        FolderRule(folderPath: "/AppB", includesDescendants: true, targetApplication: coordinatorAppB)
                    ])
    ])
}
private func makeCoordinator(opener: FakeFileOpening, timeout: TimeInterval = 5,
                             locator: AppLocating? = nil) -> OpenRequestCoordinator {
    let locator = locator ?? CoordinatorAppLocator(applications: [
        coordinatorAppA.bundleIdentifier: URL(fileURLWithPath: "/Applications/AppA.app"),
        coordinatorAppB.bundleIdentifier: URL(fileURLWithPath: "/Applications/AppB.app"),
        coordinatorFallback.bundleIdentifier: URL(fileURLWithPath: "/Applications/Fallback.app")
    ])
    return OpenRequestCoordinator(engine: RuleEngine(configuration: coordinatorConfiguration()),
                                  resolver: ApplicationResolver(locator: locator, ownBundleIdentifier: nil),
                                  opening: WorkspaceOpening(opener: opener), openByBundleID: nil,
                                  requestTimeout: timeout)
}

private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 2) throws {
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    while !condition(), ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.001) }
    try check(condition(), "后台任务未在期限内完成")
}

private final class SlowLocator: AppLocating {
    let gate = DispatchSemaphore(value: 0)
    let entered = DispatchSemaphore(value: 0)
    var missingA = false
    func urlForApplication(withBundleIdentifier id: String) -> URL? {
        if id == coordinatorAppA.bundleIdentifier {
            entered.signal()
            _ = gate.wait(timeout: .now() + 2)
            if missingA { return nil }
        }
        return URL(fileURLWithPath: "/Applications/\(id.split(separator: ".").last!).app")
    }
    func urlsForApplications(toOpen contentType: UTType) -> [URL] { [] }
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

        MiniTest.Case("后台转发同目标文件保持分组，无人工等待", {
            let fake = FakeFileOpening()
            let coordinator = makeCoordinator(opener: fake)
            coordinator.handle(urls: [URL(fileURLWithPath: "/AppA/one.pdf"), URL(fileURLWithPath: "/AppA/two.pdf")])
            try waitFor { fake.openCalls.count == 1 && !coordinator.isBusy }
            try expectEqual(fake.openCalls[0].urls.count, 2)
            try expectEqual(coordinator.recentMeasurements.count, 1)
            try check(coordinator.recentMeasurements[0].dispatchMilliseconds != nil)
        }),
        MiniTest.Case("A 未回调时 B 独立转发，同目标后续文件保持有序", {
            let fake = FakeFileOpening(); fake.completesImmediately = false
            let coordinator = makeCoordinator(opener: fake)
            coordinator.handle(urls: [URL(fileURLWithPath: "/AppA/one.pdf")])
            try waitFor { fake.openCalls.count == 1 }
            coordinator.handle(urls: [URL(fileURLWithPath: "/AppA/two.pdf"), URL(fileURLWithPath: "/AppB/three.pdf")])
            try waitFor { fake.openCalls.count == 2 }
            try expectEqual(fake.openCalls[1].appURL.lastPathComponent, "AppB.app")
            fake.complete(0)
            try waitFor { fake.openCalls.count == 3 }
            try expectEqual(fake.openCalls[2].urls[0].lastPathComponent, "two.pdf")
            fake.complete(1); fake.complete(2)
            try waitFor { !coordinator.isBusy }
        }),
        MiniTest.Case("慢应用定位不阻塞另一目标，也不依赖主线程 run loop", {
            let fake = FakeFileOpening()
            let locator = SlowLocator()
            let coordinator = makeCoordinator(opener: fake, locator: locator)
            defer { locator.gate.signal() }
            coordinator.handle(urls: [URL(fileURLWithPath: "/AppA/one.pdf")])
            try expectEqual(locator.entered.wait(timeout: .now() + 1), .success)
            coordinator.handle(urls: [URL(fileURLWithPath: "/AppB/two.pdf")])
            try waitFor { fake.openCalls.count == 1 }
            try expectEqual(fake.openCalls[0].appURL.lastPathComponent, "AppB.app")
            locator.gate.signal()
            try waitFor { !coordinator.isBusy }
        }),
        MiniTest.Case("在途路径去重，完成后允许再次打开", {
            let fake = FakeFileOpening(); fake.completesImmediately = false
            let coordinator = makeCoordinator(opener: fake)
            let url = URL(fileURLWithPath: "/AppA/reopen.pdf")
            coordinator.handle(urls: [url, url]); coordinator.handle(urls: [url])
            try waitFor { fake.openCalls.count == 1 }
            try expectEqual(fake.openCalls[0].urls.count, 1)
            fake.complete(0)
            try waitFor { !coordinator.isBusy }
            coordinator.handle(urls: [url])
            try waitFor { fake.openCalls.count == 2 }
            fake.complete(1)
            try waitFor { !coordinator.isBusy }
        }),
        MiniTest.Case("超时解除同目标阻塞，迟到回调不清理新请求", {
            let fake = FakeFileOpening(); fake.completesImmediately = false
            let coordinator = makeCoordinator(opener: fake, timeout: 0.15)
            let url = URL(fileURLWithPath: "/AppA/reopen.pdf")
            coordinator.handle(urls: [url])
            try waitFor { fake.openCalls.count == 1 }
            try waitFor { !coordinator.isBusy }
            try check(coordinator.recentErrors.contains { $0.contains("超时") })
            coordinator.handle(urls: [url])
            try waitFor { fake.openCalls.count == 2 }
            fake.complete(0)
            Thread.sleep(forTimeInterval: 0.01)
            try check(coordinator.isBusy, "旧回调不能完成新请求")
            fake.complete(1)
            try waitFor { !coordinator.isBusy }
            try expectEqual(fake.openCalls.count, 2, "超时不能自动重发")
        }),
        MiniTest.Case("配置更新不改变在途请求的 fallback，缺失目标批量降级", {
            let fake = FakeFileOpening()
            let locator = SlowLocator(); locator.missingA = true
            let coordinator = makeCoordinator(opener: fake, locator: locator)
            defer { locator.gate.signal() }
            coordinator.handle(urls: [URL(fileURLWithPath: "/AppA/one.pdf"), URL(fileURLWithPath: "/AppA/two.pdf")])
            try expectEqual(locator.entered.wait(timeout: .now() + 1), .success)
            coordinator.reload(configuration: coordinatorConfiguration(fallback: coordinatorAppB))
            locator.gate.signal()
            try waitFor { fake.openCalls.count == 1 && !coordinator.isBusy }
            try expectEqual(fake.openCalls[0].appURL.lastPathComponent, "Fallback.app")
            try expectEqual(fake.openCalls[0].urls.count, 2)
            coordinator.handle(urls: [URL(fileURLWithPath: "/Other/new.pdf")])
            try waitFor { fake.openCalls.count == 2 && !coordinator.isBusy }
            try expectEqual(fake.openCalls[1].appURL.lastPathComponent, "AppB.app")
        }),
        MiniTest.Case("错误回调后仍可打开；诊断记录有界", {
            let fake = FakeFileOpening(); fake.completesImmediately = false
            let coordinator = makeCoordinator(opener: fake)
            coordinator.handle(urls: [URL(fileURLWithPath: "/AppA/fail.pdf")])
            try waitFor { fake.openCalls.count == 1 }
            fake.complete(0, result: .failure(NSError(domain: "test", code: 1)))
            try waitFor { !coordinator.isBusy }
            try expectEqual(coordinator.recentErrors.count, 1)
            fake.completesImmediately = true
            for n in 0..<105 {
                coordinator.handle(urls: [URL(fileURLWithPath: "/AppB/\(n).pdf")])
                try waitFor { !coordinator.isBusy }
            }
            try expectEqual(coordinator.recentMeasurements.count, 100)
            try expectEqual(fake.openCalls.count, 106)
        }),
        MiniTest.Case("无路由和缺失 fallback 不残留 busy 状态", {
            let fake = FakeFileOpening()
            let coordinator = makeCoordinator(opener: fake, locator: CoordinatorAppLocator(applications: [:]))
            coordinator.handle(urls: [URL(fileURLWithPath: "/Other/file.pdf"), URL(string: "https://example.com/file.pdf")!])
            try waitFor { !coordinator.isBusy }
            try check(fake.openCalls.isEmpty)
            try expectEqual(coordinator.recentErrors.count, 1)
        }),
    ]
}
