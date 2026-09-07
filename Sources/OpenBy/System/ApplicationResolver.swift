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
// 可变缓存由 lock 保护；注入的 locator/闭包须支持并发调用。
public final class ApplicationResolver: @unchecked Sendable {
    private let locator: AppLocating
    private let ownBundleIdentifier: String?
    private let fileExists: (String) -> Bool
    private let bundleIdentifier: (URL) -> String?
    private let cacheLifetime: TimeInterval
    private let now: () -> TimeInterval
    private let lock = NSLock()
    private var generation = 0
    private struct Entry {
        let url: URL
        let expiresAt: TimeInterval
    }
    private var cache: [ApplicationReference: Entry] = [:]

    public init(
        locator: AppLocating,
        ownBundleIdentifier: String?,
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        bundleIdentifier: @escaping (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier },
        cacheLifetime: TimeInterval = 300,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.locator = locator
        self.ownBundleIdentifier = ownBundleIdentifier
        self.fileExists = fileExists
        self.bundleIdentifier = bundleIdentifier
        self.cacheLifetime = cacheLifetime
        self.now = now
    }

    /// 解析目标应用 URL；返回 nil 表示不可用（未安装 / 是自身 / lastKnownPath 失效）。
    public func applicationURL(for reference: ApplicationReference) -> URL? {
        // 防递归第一道：Bundle ID 是 OpenBy 自身。
        if let own = ownBundleIdentifier, reference.bundleIdentifier == own {
            return nil
        }
        lock.lock()
        let entry = cache[reference]
        let observedGeneration = generation
        lock.unlock()
        if let entry, entry.expiresAt > now() { return entry.url }

        // 系统查询不持锁，避免某个慢目标阻塞其他目标或设置界面。
        var resolved: URL?
        if let url = locator.urlForApplication(withBundleIdentifier: reference.bundleIdentifier) {
            if !isOwnApplication(at: url) { resolved = url }
        } else if let path = reference.lastKnownPath, fileExists(path) {
            let url = URL(fileURLWithPath: path)
            // 路径可能已被另一应用占用，后备路径必须匹配真实身份。
            if bundleIdentifier(url) == reference.bundleIdentifier, !isOwnApplication(at: url) {
                resolved = url
            }
        }
        lock.lock()
        if observedGeneration == generation {
            if cache.count >= 128 { cache.removeAll(keepingCapacity: true) }
            cache[reference] = resolved.map { Entry(url: $0, expiresAt: now() + cacheLifetime) }
        }
        lock.unlock()
        // 不缓存缺失结果，安装或移动后下一个请求即可重新定位。
        return resolved
    }

    public func invalidate(bundleIdentifier: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        if let bundleIdentifier {
            cache = cache.filter { $0.key.bundleIdentifier != bundleIdentifier }
        } else {
            cache.removeAll(keepingCapacity: true)
        }
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
        return bundleIdentifier(url) == own
    }
}
