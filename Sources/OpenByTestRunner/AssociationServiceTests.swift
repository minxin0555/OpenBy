import Foundation
import OpenBy
import UniformTypeIdentifiers

/// 注入的 fake：不触碰真实系统默认关联。
private final class FakeDefaultAppProvider: DefaultAppProviding {
    var currentBundleID: String?
    var installedURLs: [String: URL] = [:]
    var setDefaultError: Error?
    /// 模拟 setDefaultApplication 成功后当前默认变为该 Bundle ID。
    var setDefaultSetsCurrentTo: String?
    var setDefaultCalls: [(appURL: URL, contentType: UTType)] = []

    func currentDefaultApplicationBundleID(toOpen contentType: UTType) -> String? { currentBundleID }

    func currentDefaultApplicationURL(toOpen contentType: UTType) -> URL? {
        currentBundleID.flatMap { installedURLs[$0] }
    }

    func setDefaultApplication(_ appURL: URL, toOpen contentType: UTType, completion: @escaping (Error?) -> Void) {
        setDefaultCalls.append((appURL, contentType))
        if let setDefaultSetsCurrentTo {
            currentBundleID = setDefaultSetsCurrentTo
        }
        completion(setDefaultError)
    }

    func applicationURL(withBundleIdentifier bundleIdentifier: String) -> URL? {
        installedURLs[bundleIdentifier]
    }
}

enum AssociationServiceTests {
    static let openByBundleID = "com.example.OpenBy"
    static let contentType = UTType.pdf
    static let previewURL = URL(fileURLWithPath: "/System/Applications/Preview.app")

    static let cases: [MiniTest.Case] = [
        MiniTest.Case("整组启用覆盖全部类型，重试跳过已启用类型", {
            let fake = GroupDefaultAppProvider()
            fake.current = [UTType.jpeg.identifier: "original.image", UTType.png.identifier: "original.png"]
            let service = AssociationService(provider: fake, verifyAttempts: 0)
            var captured: Result<Bool, Error>?
            service.takeOverGroup(contentTypes: [.jpeg, .png], targetAppURL: fake.openByURL,
                                  openByBundleID: openByBundleID) { captured = $0 }
            try expectEqual(try expectNotNil(captured).get(), true)
            try expectEqual(fake.calls, [UTType.jpeg.identifier, UTType.png.identifier])
            service.takeOverGroup(contentTypes: [.jpeg, .png], targetAppURL: fake.openByURL,
                                  openByBundleID: openByBundleID) { captured = $0 }
            try expectEqual(fake.calls.count, 2)
        }),
        MiniTest.Case("整组启用部分失败后可恢复每种格式原应用", {
            let fake = GroupDefaultAppProvider()
            fake.current = [UTType.jpeg.identifier: "original.image", UTType.png.identifier: "original.png"]
            fake.rejectedType = UTType.png.identifier
            let service = AssociationService(provider: fake, verifyAttempts: 0)
            var captured: Result<Bool, Error>?
            service.takeOverGroup(contentTypes: [.jpeg, .png], targetAppURL: fake.openByURL,
                                  openByBundleID: openByBundleID) { captured = $0 }
            try expectEqual(try expectNotNil(captured).get(), false)
            try expectEqual(fake.current[UTType.jpeg.identifier], openByBundleID)
            fake.rejectedType = nil
            let originals = [UTType.jpeg.identifier: ApplicationReference(bundleIdentifier: "original.image", displayName: "Images"),
                             UTType.png.identifier: ApplicationReference(bundleIdentifier: "original.png", displayName: "PNG")]
            service.restoreGroup(contentTypes: [.jpeg, .png], previous: originals,
                                 openByBundleID: openByBundleID) { captured = $0 }
            try expectEqual(try expectNotNil(captured).get(), true)
            try expectEqual(fake.current[UTType.jpeg.identifier], "original.image")
            try expectEqual(fake.current[UTType.png.identifier], "original.png")
        }),
        MiniTest.Case("整组恢复各自原应用且保留用户后来手动选择", {
            let fake = GroupDefaultAppProvider()
            fake.current = [UTType.jpeg.identifier: openByBundleID, UTType.png.identifier: openByBundleID,
                            UTType.pdf.identifier: "user.choice"]
            let service = AssociationService(provider: fake, verifyAttempts: 0)
            let originals = [UTType.jpeg.identifier: ApplicationReference(bundleIdentifier: "original.image", displayName: "Images"),
                             UTType.png.identifier: ApplicationReference(bundleIdentifier: "original.png", displayName: "PNG")]
            var captured: Result<Bool, Error>?
            service.restoreGroup(contentTypes: [.jpeg, .png, .pdf], previous: originals,
                                 openByBundleID: openByBundleID) { captured = $0 }
            try expectEqual(try expectNotNil(captured).get(), true)
            try expectEqual(fake.current[UTType.jpeg.identifier], "original.image")
            try expectEqual(fake.current[UTType.png.identifier], "original.png")
            try expectEqual(fake.current[UTType.pdf.identifier], "user.choice")
        }),
        MiniTest.Case("缺少组成员恢复记录时不能宣称整组恢复完成", {
            let fake = GroupDefaultAppProvider()
            fake.current = [UTType.png.identifier: openByBundleID]
            let service = AssociationService(provider: fake, verifyAttempts: 0)
            var captured: Result<Bool, Error>?
            service.restoreGroup(contentTypes: [.png], previous: [:], openByBundleID: openByBundleID) { captured = $0 }
            try expectEqual(try expectNotNil(captured).get(), false)
            try check(fake.calls.isEmpty)
        }),
        // MARK: 接管前记录原默认
        MiniTest.Case("接管前：当前默认是其他应用 → 返回其引用", {
            let fake = FakeDefaultAppProvider()
            fake.currentBundleID = "com.apple.Preview"
            fake.installedURLs["com.apple.Preview"] = previewURL
            let service = AssociationService(provider: fake)
            let previous = try expectNotNil(service.previousDefaultApplication(for: contentType, unlessBundleID: openByBundleID))
            try expectEqual(previous.bundleIdentifier, "com.apple.Preview")
        }),
        MiniTest.Case("接管前：当前默认已是 OpenBy → nil", {
            let fake = FakeDefaultAppProvider()
            fake.currentBundleID = openByBundleID
            let service = AssociationService(provider: fake)
            try expectNil(service.previousDefaultApplication(for: contentType, unlessBundleID: openByBundleID))
        }),
        MiniTest.Case("接管前：默认未知 → nil", {
            let fake = FakeDefaultAppProvider()
            fake.currentBundleID = nil
            let service = AssociationService(provider: fake)
            try expectNil(service.previousDefaultApplication(for: contentType, unlessBundleID: openByBundleID))
        }),

        // MARK: 接管
        MiniTest.Case("接管成功并验证", {
            let fake = FakeDefaultAppProvider()
            fake.currentBundleID = "com.apple.Preview"
            fake.setDefaultSetsCurrentTo = openByBundleID
            let service = AssociationService(provider: fake)
            var captured: Result<Bool, Error>?
            service.takeOver(contentType: contentType, targetAppURL: previewURL, openByBundleID: openByBundleID) {
                captured = $0
            }
            let result = try expectNotNil(captured)
            try expectEqual(try result.get(), true)
            try expectEqual(fake.setDefaultCalls.count, 1)
        }),
        MiniTest.Case("接管被用户拒绝（设置返回错误）→ failure", {
            let fake = FakeDefaultAppProvider()
            fake.setDefaultError = NSError(domain: "test", code: 1)
            let service = AssociationService(provider: fake)
            var captured: Result<Bool, Error>?
            service.takeOver(contentType: contentType, targetAppURL: previewURL, openByBundleID: openByBundleID) {
                captured = $0
            }
            try check(captured.map { (try? $0.get()) == nil } == true, "应失败")
        }),
        MiniTest.Case("接管后重读不是 OpenBy（用户拒绝/未生效）→ success(false)", {
            let fake = FakeDefaultAppProvider()
            fake.currentBundleID = "com.apple.Preview" // setDefault 成功但读回仍是 Preview
            // verifyAttempts: 0 → 同步完成（生产默认 6×0.5s 轮询，测试保持确定性）。
            let service = AssociationService(provider: fake, verifyAttempts: 0)
            var captured: Result<Bool, Error>?
            service.takeOver(contentType: contentType, targetAppURL: previewURL, openByBundleID: openByBundleID) {
                captured = $0
            }
            try expectEqual(try expectNotNil(captured).get(), false)
        }),

        // MARK: 恢复
        MiniTest.Case("恢复：当前默认不是 OpenBy → 不执行（尊重用户手动选择）", {
            let fake = FakeDefaultAppProvider()
            fake.currentBundleID = "com.someone.Other"
            let service = AssociationService(provider: fake)
            var captured: Result<Bool, Error>?
            service.restorePreviousDefault(
                contentType: contentType,
                previous: ApplicationReference(bundleIdentifier: "com.apple.Preview", displayName: "Preview"),
                openByBundleID: openByBundleID
            ) { captured = $0 }
            try expectEqual(try expectNotNil(captured).get(), false)
            try expectEqual(fake.setDefaultCalls.count, 0)
        }),
        MiniTest.Case("恢复：当前默认是 OpenBy → 执行并验证", {
            let fake = FakeDefaultAppProvider()
            fake.currentBundleID = openByBundleID
            fake.installedURLs["com.apple.Preview"] = previewURL
            fake.setDefaultSetsCurrentTo = "com.apple.Preview"
            let service = AssociationService(provider: fake)
            var captured: Result<Bool, Error>?
            service.restorePreviousDefault(
                contentType: contentType,
                previous: ApplicationReference(bundleIdentifier: "com.apple.Preview", displayName: "Preview"),
                openByBundleID: openByBundleID
            ) { captured = $0 }
            try expectEqual(try expectNotNil(captured).get(), true)
            try expectEqual(fake.setDefaultCalls.count, 1)
            try expectEqual(fake.setDefaultCalls[0].appURL, previewURL)
        }),
        MiniTest.Case("恢复：previous 应用已不存在 → 不执行", {
            let fake = FakeDefaultAppProvider()
            fake.currentBundleID = openByBundleID
            fake.installedURLs = [:] // previous 未安装
            let service = AssociationService(provider: fake)
            var captured: Result<Bool, Error>?
            service.restorePreviousDefault(
                contentType: contentType,
                previous: ApplicationReference(bundleIdentifier: "com.apple.Preview", displayName: "Preview"),
                openByBundleID: openByBundleID
            ) { captured = $0 }
            try expectEqual(try expectNotNil(captured).get(), false)
            try expectEqual(fake.setDefaultCalls.count, 0)
        }),

        // MARK: 接管状态
        MiniTest.Case("isManagedByOpenBy 判定", {
            let fake = FakeDefaultAppProvider()
            fake.currentBundleID = openByBundleID
            let service = AssociationService(provider: fake)
            try check(service.isManagedByOpenBy(contentType: contentType, openByBundleID: openByBundleID))
            fake.currentBundleID = "com.apple.Preview"
            try check(!service.isManagedByOpenBy(contentType: contentType, openByBundleID: openByBundleID))
        }),
    ]
}

private final class GroupDefaultAppProvider: DefaultAppProviding {
    let openByURL = URL(fileURLWithPath: "/Applications/com.example.OpenBy.app")
    var current: [String: String] = [:]
    var calls: [String] = []
    var rejectedType: String?
    func currentDefaultApplicationBundleID(toOpen contentType: UTType) -> String? { current[contentType.identifier] }
    func currentDefaultApplicationURL(toOpen contentType: UTType) -> URL? {
        current[contentType.identifier].flatMap(applicationURL(withBundleIdentifier:))
    }
    func applicationURL(withBundleIdentifier bundleIdentifier: String) -> URL? {
        URL(fileURLWithPath: "/Applications/\(bundleIdentifier).app")
    }
    func setDefaultApplication(_ appURL: URL, toOpen contentType: UTType, completion: @escaping (Error?) -> Void) {
        calls.append(contentType.identifier)
        if rejectedType != contentType.identifier {
            current[contentType.identifier] = appURL.deletingPathExtension().lastPathComponent
        }
        completion(nil)
    }
}
