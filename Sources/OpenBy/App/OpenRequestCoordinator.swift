import AppKit
import Foundation

/// 打开请求协调器：冷/热启动缓冲、批量合并与去重、按目标分组转发、目标缺失降级、
/// 保活-退出决策。全部状态主线程访问。
///
/// 生命周期（对应文档第 15 节第 2 项）：收到新事件重置保活计时器（默认 3s）；
/// 空闲后 flush → 转发 → 若设置窗口不可见则自动退出。
@MainActor
public final class OpenRequestCoordinator {
    public let keepAliveInterval: TimeInterval
    /// 空闲时是否允许退出（AppDelegate 注入：设置窗口可见则返回 false）。
    public var shouldTerminateIfIdle: () -> Bool = { true }

    private var engine: RuleEngine
    private let resolver: ApplicationResolver
    private let opening: WorkspaceOpening
    private let openByBundleID: String?

    private var pending: [URL] = []
    private var seenPaths = Set<String>()
    private var workItem: DispatchWorkItem?
    private var isFlushing = false
    private var deferred: [URL] = []

    /// 仅内存保留的最近错误（诊断页展示），路径做用户目录缩写，不落盘。
    public private(set) var recentErrors: [String] = []
    private let maxErrors = 20

    public init(
        engine: RuleEngine,
        resolver: ApplicationResolver,
        opening: WorkspaceOpening,
        openByBundleID: String?,
        keepAliveInterval: TimeInterval = 3.0
    ) {
        self.engine = engine
        self.resolver = resolver
        self.opening = opening
        self.openByBundleID = openByBundleID
        self.keepAliveInterval = keepAliveInterval
    }

    /// 是否仍有在途请求（AppDelegate 用它决定窗口关闭时是否可退出）。
    public var isBusy: Bool {
        isFlushing || !pending.isEmpty || !deferred.isEmpty
    }

    /// 配置变更后热更新规则引擎（设置窗口保存后调用）。
    public func reload(configuration: Configuration) {
        engine = RuleEngine(configuration: configuration)
    }

    /// 接收文件 URL（主线程调用）。
    public func handle(urls: [URL]) {
        for url in urls {
            guard url.isFileURL else { continue }
            let standardized = url.standardizedFileURL
            guard seenPaths.insert(standardized.path).inserted else { continue }
            pending.append(standardized)
        }
        guard !pending.isEmpty else { return }
        resetKeepAlive()
    }

    // MARK: - 保活

    private func resetKeepAlive() {
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in self?.flush() }
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + keepAliveInterval, execute: item)
    }

    private func flush() {
        // flush 期间又来事件：并入 deferred，本次 flush 完成后重排。
        if isFlushing {
            deferred.append(contentsOf: pending)
            pending.removeAll()
            return
        }
        isFlushing = true
        let batch = pending
        pending.removeAll()

        process(batch) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isFlushing = false
                if !self.deferred.isEmpty {
                    self.pending.append(contentsOf: self.deferred)
                    self.deferred.removeAll()
                    self.resetKeepAlive()
                } else {
                    self.maybeTerminate()
                }
            }
        }
    }

    // MARK: - 路由

    private func process(_ urls: [URL], completion: @escaping () -> Void) {
        let result = BatchRouter.group(urls, engine: engine)
        for url in result.unrouted {
            recordError("无法路由: \(Self.redacted(url.path))")
        }

        let group = DispatchGroup()

        for (target, targetURLs) in result.groups {
            if let appURL = resolver.applicationURL(for: target) {
                group.enter()
                opening.open(targetURLs, in: appURL, openByBundleID: openByBundleID) { [weak self] result in
                    if case .failure(let error) = result {
                        self?.recordError("\(target.displayName): \(error.localizedDescription)")
                    }
                    group.leave()
                }
            } else {
                // 目标应用缺失 → 逐文件降级到其 handler 的 fallback（本身就是 fallback 的则报错）。
                fallbackForMissingTarget(target: target, urls: targetURLs, group: group)
            }
        }

        group.notify(queue: .main) { completion() }
    }

    private func fallbackForMissingTarget(target: ApplicationReference, urls: [URL], group: DispatchGroup) {
        for url in urls {
            // 只有命中规则（.rule）才降级到 fallback；命中 fallback 本身则无更低级可降。
            guard case .rule = engine.resolveDecision(for: url),
                  let fallback = engine.fallbackApplication(for: url),
                  fallback != target else {
                recordError("目标应用缺失: \(Self.redacted(url.path))")
                continue
            }
            guard let fallbackURL = resolver.applicationURL(for: fallback) else {
                recordError("目标与回退应用均缺失: \(Self.redacted(url.path))")
                continue
            }
            group.enter()
            opening.open([url], in: fallbackURL, openByBundleID: openByBundleID) { [weak self] result in
                if case .failure(let error) = result {
                    self?.recordError("\(fallback.displayName): \(error.localizedDescription)")
                }
                group.leave()
            }
        }
    }

    // MARK: - 退出

    private func maybeTerminate() {
        guard shouldTerminateIfIdle() else { return }
        // 退出前小宽限，吸收"flush 恰逢下一批到达"的边界。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.isBusy else { return }
            NSApp.terminate(nil)
        }
    }

    private func recordError(_ message: String) {
        recentErrors.append(message)
        if recentErrors.count > maxErrors {
            recentErrors.removeFirst(recentErrors.count - maxErrors)
        }
    }

    /// 隐私：用户目录缩写为 `~`。
    static func redacted(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
