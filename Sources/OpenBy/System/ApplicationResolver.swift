import AppKit
import UniformTypeIdentifiers

/// 应用定位能力（协议化便于注入 fake）。
public protocol AppLocating {
    func urlForApplication(withBundleIdentifier: String) -> URL?
    func urlsForApplications(toOpen contentType: UTType) -> [URL]
}

/// NSWorkspace 实现。
public final class WorkspaceAppLocator: AppLocating {
    public init() {}

    public func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    public func urlsForApplications(toOpen contentType: UTType) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: contentType)
    }
}

/// Bundle ID → 应用 URL；过滤 OpenBy 自身；`lastKnownPath` 只作显示与后备。
/// 只在设置 UI 枚举应用（`installedApplications`），绝不在路由热路径调用。
public struct ApplicationResolver {
    private let locator: AppLocating
    private let ownBundleIdentifier: String?
    private let fileExists: (String) -> Bool

    public init(
        locator: AppLocating,
        ownBundleIdentifier: String?,
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.locator = locator
        self.ownBundleIdentifier = ownBundleIdentifier
        self.fileExists = fileExists
    }

    /// 解析目标应用 URL；返回 nil 表示不可用（未安装 / 是自身 / lastKnownPath 失效）。
    public func applicationURL(for reference: ApplicationReference) -> URL? {
        // 防递归第一道：Bundle ID 是 OpenBy 自身。
        if let own = ownBundleIdentifier, reference.bundleIdentifier == own {
            return nil
        }
        if let url = locator.urlForApplication(withBundleIdentifier: reference.bundleIdentifier) {
            return isOwnApplication(at: url) ? nil : url
        }
        // lastKnownPath 兜底（应用被移动但路径仍存在）。
        if let path = reference.lastKnownPath, fileExists(path) {
            let url = URL(fileURLWithPath: path)
            return isOwnApplication(at: url) ? nil : url
        }
        return nil
    }

    /// 枚举可打开该类型的应用（设置 UI 用，过滤自身）。
    public func installedApplications(toOpen contentType: UTType) -> [ApplicationReference] {
        locator.urlsForApplications(toOpen: contentType).compactMap { url in
            let bundleID = Bundle(url: url)?.bundleIdentifier
            if bundleID == ownBundleIdentifier { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            return ApplicationReference(bundleIdentifier: bundleID ?? "", lastKnownPath: url.path, displayName: name)
        }
    }

    private func isOwnApplication(at url: URL) -> Bool {
        guard let own = ownBundleIdentifier else { return false }
        return Bundle(url: url)?.bundleIdentifier == own
    }
}
