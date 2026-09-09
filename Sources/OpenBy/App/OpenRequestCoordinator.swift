import AppKit
import Foundation

/// 有界、仅内存的请求计时。系统回调完成不代表文档窗口已经显示。
public struct RoutingMeasurement {
    public let id: UUID
    public let target: String
    public let fileCount: Int
    public let routingMilliseconds: Double
    public let queueMilliseconds: Double
    public let resolutionMilliseconds: Double
    public let dispatchMilliseconds: Double?
    public var completionMilliseconds: Double?
    public var status: String
}

/// 后台串行队列管理状态；每个目标独立定位和转发，不等待其他应用的回调。
/// 不负责退出进程：OpenBy 在空闲和关闭设置窗口后继续常驻。
public final class OpenRequestCoordinator {
    private let queue = DispatchQueue(label: "OpenBy.routing", qos: .userInitiated)
    private var engine: RuleEngine
    private let resolver: ApplicationResolver
    private let opening: WorkspaceOpening
    private let openByBundleID: String?
    private let requestTimeout: TimeInterval
    private var seenPaths = Set<String>()
    private var lanes: [String: Lane] = [:]
    private var errors: [String] = []
    private var measurements: [RoutingMeasurement] = []

    private struct Item {
        let url: URL
        let target: ApplicationReference
        let fallback: ApplicationReference?
        let receivedAt: TimeInterval
        let routingMilliseconds: Double
    }
    private struct Job {
        let id: UUID
        let items: [Item]
        let startedAt: TimeInterval
        let timeout: DispatchWorkItem
    }
    private struct Lane {
        var active: Job?
        var pending: [Item] = []
    }

    public init(
        engine: RuleEngine,
        resolver: ApplicationResolver,
        opening: WorkspaceOpening,
        openByBundleID: String?,
        requestTimeout: TimeInterval = 30
    ) {
        self.engine = engine
        self.resolver = resolver
        self.opening = opening
        self.openByBundleID = openByBundleID
        self.requestTimeout = max(0.01, requestTimeout)
    }

    public var isBusy: Bool { queue.sync { !lanes.isEmpty } }
    public var recentErrors: [String] { queue.sync { errors } }
    public var recentMeasurements: [RoutingMeasurement] { queue.sync { measurements } }

    /// 与 handle 在同一串行队列提交：保存后的下一批请求使用新配置。
    /// 已在途/排队的 Item 自带原配置的 fallback，不受后续编辑影响。
    public func reload(configuration: Configuration) {
        queue.async {
            self.engine = RuleEngine(configuration: configuration)
            self.resolver.invalidate()
        }
    }

    public func invalidateApplications() { resolver.invalidate() }

    public func handle(urls: [URL], receivedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        queue.async {
            let routingStart = Self.now
            var items: [Item] = []
            for url in urls where url.isFileURL {
                let url = url.standardizedFileURL
                guard self.seenPaths.insert(url.path).inserted else { continue }
                let decision = self.engine.resolveDecision(for: url)
                let target: ApplicationReference
                let fallback: ApplicationReference?
                switch decision {
                case .rule(let application):
                    target = application
                    fallback = self.engine.fallbackApplication(for: url)
                case .fallback(let application):
                    target = application
                    fallback = nil
                case .none:
                    self.seenPaths.remove(url.path)
                    self.recordError("无法路由: \(Self.redacted(url.path))")
                    continue
                }
                items.append(Item(url: url, target: target, fallback: fallback,
                                  receivedAt: receivedAt, routingMilliseconds: (Self.now - routingStart) * 1000))
            }
            self.enqueue(items)
        }
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func enqueue(_ items: [Item]) {
        var targets: [String] = []
        for item in items {
            let key = item.target.bundleIdentifier
            if !targets.contains(key) { targets.append(key) }
            lanes[key, default: Lane()].pending.append(item)
        }
        for key in targets { startNext(for: key) }
    }

    private func startNext(for key: String) {
        guard var lane = lanes[key], lane.active == nil else { return }
        guard !lane.pending.isEmpty else { lanes.removeValue(forKey: key); return }
        let items = lane.pending
        lane.pending.removeAll()
        let id = UUID()
        let timeout = DispatchWorkItem { [weak self] in self?.timedOut(key: key, id: id) }
        let job = Job(id: id, items: items, startedAt: Self.now, timeout: timeout)
        lane.active = job
        lanes[key] = lane
        queue.asyncAfter(deadline: .now() + requestTimeout, execute: timeout)

        // NSWorkspace 查找可能慢：每个目标独立执行，状态队列不做系统 I/O。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let appURL = self.resolver.applicationURL(for: items[0].target)
            let resolution = (Self.now - job.startedAt) * 1000
            self.queue.async {
                guard self.lanes[key]?.active?.id == id else { return }
                guard let appURL else {
                    self.missingTarget(key: key, job: job, resolution: resolution)
                    return
                }
                self.dispatch(job: job, key: key, appURL: appURL, resolution: resolution)
            }
        }
    }

    private func dispatch(job: Job, key: String, appURL: URL, resolution: Double) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.opening.open(job.items.map(\.url), in: appURL, openByBundleID: self.openByBundleID, willOpen: {
                self.queue.sync {
                    guard self.lanes[key]?.active?.id == job.id else { return false }
                    self.appendMeasurement(job: job, resolution: resolution, dispatchedAt: Self.now, status: "已转发")
                    return true
                }
            }) { [weak self] result in
                guard let self else { return }
                self.queue.async {
                    guard self.lanes[key]?.active?.id == job.id else { return }
                    if !self.measurements.contains(where: { $0.id == job.id }) {
                        self.appendMeasurement(job: job, resolution: resolution, dispatchedAt: nil, status: "未转发")
                    }
                    if case .failure(let error) = result {
                        self.resolver.invalidate(bundleIdentifier: key)
                        self.recordError("\(job.items[0].target.displayName): \(error.localizedDescription)")
                        self.finishMeasurement(job: job, status: "转发失败")
                    } else {
                        self.finishMeasurement(job: job, status: "系统已确认")
                    }
                    self.finish(key: key, job: job)
                }
            }
        }
    }

    private func missingTarget(key: String, job: Job, resolution: Double) {
        appendMeasurement(job: job, resolution: resolution, dispatchedAt: nil, status: "目标缺失")
        var fallbacks: [Item] = []
        for item in job.items {
            if let fallback = item.fallback, fallback.bundleIdentifier != key {
                fallbacks.append(Item(url: item.url, target: fallback, fallback: nil,
                                      receivedAt: item.receivedAt, routingMilliseconds: item.routingMilliseconds))
            } else {
                seenPaths.remove(item.url.path)
                recordError("目标应用缺失: \(Self.redacted(item.url.path))")
            }
        }
        job.timeout.cancel()
        lanes[key]?.active = nil
        // 缺失目标的 fallback 也走目标队列，批量合并且不覆盖其他在途请求。
        enqueue(fallbacks)
        startNext(for: key)
    }

    private func timedOut(key: String, id: UUID) {
        guard let job = lanes[key]?.active, job.id == id else { return }
        resolver.invalidate(bundleIdentifier: key)
        recordError("\(job.items[0].target.displayName): 打开请求超时，未自动重发；请检查目标应用")
        if measurements.contains(where: { $0.id == id }) {
            finishMeasurement(job: job, status: "超时")
        } else {
            appendMeasurement(job: job, resolution: (Self.now - job.startedAt) * 1000,
                              dispatchedAt: nil, status: "定位超时")
        }
        finish(key: key, job: job)
    }

    private func finish(key: String, job: Job) {
        job.timeout.cancel()
        for item in job.items { seenPaths.remove(item.url.path) }
        lanes[key]?.active = nil
        startNext(for: key)
    }

    private func appendMeasurement(job: Job, resolution: Double, dispatchedAt: TimeInterval?, status: String) {
        let received = job.items.map(\.receivedAt).min() ?? job.startedAt
        let route = job.items.map(\.routingMilliseconds).max() ?? 0
        measurements.append(RoutingMeasurement(
            id: job.id, target: job.items[0].target.displayName, fileCount: job.items.count,
            routingMilliseconds: route,
            queueMilliseconds: max(0, (job.startedAt - received) * 1000 - route),
            resolutionMilliseconds: resolution,
            dispatchMilliseconds: dispatchedAt.map { ($0 - received) * 1000 },
            completionMilliseconds: nil, status: status
        ))
        if measurements.count > 100 { measurements.removeFirst(measurements.count - 100) }
    }

    private func finishMeasurement(job: Job, status: String) {
        guard let index = measurements.firstIndex(where: { $0.id == job.id }) else { return }
        let received = job.items.map(\.receivedAt).min() ?? job.startedAt
        measurements[index].completionMilliseconds = (Self.now - received) * 1000
        measurements[index].status = status
    }

    private func recordError(_ message: String) {
        errors.append(message)
        if errors.count > 20 { errors.removeFirst(errors.count - 20) }
    }

    static func redacted(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home || path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
