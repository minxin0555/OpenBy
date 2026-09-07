import AppKit

/// 文件打开能力。协议**只有**"显式指定目标应用"的入口——
/// 从结构上杜绝"不指定应用的 open"，防止系统默认处理器（正是 OpenBy）被递归调用。
/// 实现必须支持不同目标从后台线程并发调用；completion 可从任意队列返回。
public protocol FileOpening {
    func open(_ urls: [URL], withApplicationAt appURL: URL, completion: @escaping (Result<Void, Error>) -> Void)
}

/// 转发门面：附加防递归校验后交给底层 opener。
public struct WorkspaceOpening {
    private let opener: FileOpening

    public init(opener: FileOpening) {
        self.opener = opener
    }

    /// 显式转发。`openByBundleID` 为 OpenBy 自身时再次比对目标（配置层已禁止，这里是防御性兜底）。
    public func open(_ urls: [URL], in applicationURL: URL, openByBundleID: String?, willOpen: () -> Bool = { true }, completion: @escaping (Result<Void, Error>) -> Void) {
        if let openByBundleID, Bundle(url: applicationURL)?.bundleIdentifier == openByBundleID {
            completion(.failure(RoutingError.recursiveTarget(bundleIdentifier: openByBundleID)))
            return
        }
        guard willOpen() else { return }
        opener.open(urls, withApplicationAt: applicationURL, completion: completion)
    }
}

/// 真实现：只调用 `NSWorkspace.open(_:withApplicationAt:configuration:)`，绝不调用裸 `open(_:)`。
public final class WorkspaceFileOpening: FileOpening {
    public init() {}

    public func open(_ urls: [URL], withApplicationAt appURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
}
