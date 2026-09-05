import AppKit
import CoreServices
import UniformTypeIdentifiers

/// 默认应用关联的低层能力。协议化以便注入 fake，避免单元测试污染真实系统默认关联。
public protocol DefaultAppProviding {
    /// 当前该类型的默认处理应用 Bundle ID。
    func currentDefaultApplicationBundleID(toOpen contentType: UTType) -> String?
    /// 当前该类型的默认处理应用 URL。
    func currentDefaultApplicationURL(toOpen contentType: UTType) -> URL?
    /// 把某应用设为该类型的默认处理器。
    func setDefaultApplication(_ appURL: URL, toOpen contentType: UTType, completion: @escaping (Error?) -> Void)
    /// 按 Bundle ID 查应用 URL。
    func applicationURL(withBundleIdentifier: String) -> URL?
}

/// NSWorkspace 实现。现代 API 为主，Launch Services C API 仅作失败兜底。
public final class WorkspaceDefaultAppProvider: DefaultAppProviding {
    public init() {}

    public func currentDefaultApplicationBundleID(toOpen contentType: UTType) -> String? {
        guard let url = currentDefaultApplicationURL(toOpen: contentType) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    public func currentDefaultApplicationURL(toOpen contentType: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: contentType)
    }

    public func setDefaultApplication(_ appURL: URL, toOpen contentType: UTType, completion: @escaping (Error?) -> Void) {
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: contentType) { error in
            if error == nil {
                completion(nil)
                return
            }
            // 兜底：LS C API（隔离在本 Provider 内）。
            guard let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
                completion(error)
                return
            }
            // kLSRolesViewer = 0x02（C 宏未导入 Swift，直接使用数值常量）。
            let viewerRole = LSRolesMask(rawValue: 0x02)
            let status = LSSetDefaultRoleHandlerForContentType(
                contentType.identifier as CFString,
                viewerRole,
                bundleID as CFString
            )
            if status == noErr {
                completion(nil)
            } else {
                completion(NSError(domain: NSOSStatusErrorDomain, code: Int(status)))
            }
        }
    }

    public func applicationURL(withBundleIdentifier bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}

/// 默认关联业务逻辑：接管前记录原默认、设置后重读验证、恢复时尊重用户后续手动选择。
/// 所有与 NSWorkspace 的接触都经由注入的 `DefaultAppProviding`，逻辑本身可单测。
public final class AssociationService {
    private let provider: DefaultAppProviding
    /// 默认关联生效验证轮询参数（测试可注入为 0 保持同步）。
    private let verifyAttempts: Int
    private let verifyInterval: TimeInterval

    public init(provider: DefaultAppProviding, verifyAttempts: Int = 6, verifyInterval: TimeInterval = 0.5) {
        self.provider = provider
        self.verifyAttempts = verifyAttempts
        self.verifyInterval = verifyInterval
    }

    /// 接管前读取原默认应用；若当前默认已是 OpenBy 或查询失败则返回 nil
    /// （调用方不应覆盖已保存的 previousDefaultApplication）。
    public func previousDefaultApplication(for contentType: UTType, unlessBundleID openByBundleID: String) -> ApplicationReference? {
        guard let bundleID = provider.currentDefaultApplicationBundleID(toOpen: contentType),
              bundleID != openByBundleID else {
            return nil
        }
        let url = provider.applicationURL(withBundleIdentifier: bundleID)
        let name = url?.deletingPathExtension().lastPathComponent ?? bundleID
        return ApplicationReference(bundleIdentifier: bundleID, lastKnownPath: url?.path, displayName: name)
    }

    /// 当前默认是否已被 OpenBy 接管。
    public func isManagedByOpenBy(contentType: UTType, openByBundleID: String) -> Bool {
        provider.currentDefaultApplicationBundleID(toOpen: contentType) == openByBundleID
    }

    /// 当前该类型的默认应用 Bundle ID（设置界面展示用）。
    public func currentDefaultApplicationBundleID(for contentType: UTType) -> String? {
        provider.currentDefaultApplicationBundleID(toOpen: contentType)
    }

    /// 异步接管：设置默认，完成后重读验证（macOS 26.4+ 可能弹系统确认框，当正常流程）。
    /// Result.success(true) = 已接管；false = 用户拒绝或尚未生效。
    public func takeOver(
        contentType: UTType,
        targetAppURL: URL,
        openByBundleID: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        provider.setDefaultApplication(targetAppURL, toOpen: contentType) { [weak self] error in
            guard let self else { return }
            if let error {
                completion(.failure(error))
                return
            }
            // 系统关联生效可能有延迟（E2E 实测 completion 返回后仍短暂读到旧默认），轮询确认。
            self.pollForDefault(
                becoming: openByBundleID,
                contentType: contentType,
                attempts: self.verifyAttempts,
                interval: self.verifyInterval
            ) { isNowOpenBy in
                completion(.success(isNowOpenBy))
            }
        }
    }

    /// 轮询直到系统默认关联等于 `bundleID`（或超时）。completion 在后台队列。
    private func pollForDefault(
        becoming bundleID: String,
        contentType: UTType,
        attempts: Int,
        interval: TimeInterval,
        done: @escaping (Bool) -> Void
    ) {
        if isManagedByOpenBy(contentType: contentType, openByBundleID: bundleID) {
            done(true)
            return
        }
        guard attempts > 0 else {
            done(false)
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.pollForDefault(becoming: bundleID, contentType: contentType, attempts: attempts - 1, interval: interval, done: done)
        }
    }

    /// 恢复 previous 为默认。仅当"当前默认仍是 OpenBy"才恢复，绝不覆盖用户后来手动做出的选择。
    /// Result.success(true) = 已恢复；false = 未执行（当前默认已不是 OpenBy，或 previous 应用已不存在）。
    public func restorePreviousDefault(
        contentType: UTType,
        previous: ApplicationReference,
        openByBundleID: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard isManagedByOpenBy(contentType: contentType, openByBundleID: openByBundleID) else {
            completion(.success(false))
            return
        }
        guard let url = provider.applicationURL(withBundleIdentifier: previous.bundleIdentifier) else {
            completion(.success(false))
            return
        }
        provider.setDefaultApplication(url, toOpen: contentType) { [weak self] error in
            guard let self else { return }
            if let error {
                completion(.failure(error))
                return
            }
            self.pollForDefault(
                becoming: previous.bundleIdentifier,
                contentType: contentType,
                attempts: self.verifyAttempts,
                interval: self.verifyInterval
            ) { restored in
                completion(.success(restored))
            }
        }
    }
}
