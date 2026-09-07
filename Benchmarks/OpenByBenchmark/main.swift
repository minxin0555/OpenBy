import Foundation
import OpenBy
import UniformTypeIdentifiers

// --pipeline 测收到事件到调用 FileOpening（真实应用定位、假打开，不显示用户文档）。
let args = Array(CommandLine.arguments.dropFirst())
func number(_ flag: String, default fallback: Int) -> Int {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count, let n = Int(args[i + 1]), n > 0 else { return fallback }
    return n
}
let ruleCount = number("--rules", default: 1000)
let iterations = number("--iterations", default: 2000)
let target = ApplicationReference(bundleIdentifier: "com.apple.Preview", displayName: "Preview")
let rules = (0..<ruleCount).map {
    FolderRule(folderPath: "/BenchmarkDir\($0)", includesDescendants: true, targetApplication: target)
}
let configuration = Configuration(schemaVersion: 1, handlers: [
    FileHandler(contentTypeIdentifier: UTType.pdf.identifier, fallbackApplication: target, displayExtensions: ["pdf"], rules: rules)
])
let started = ProcessInfo.processInfo.systemUptime
let engine = RuleEngine(configuration: configuration)
let initialization = (ProcessInfo.processInfo.systemUptime - started) * 1000
let matchedURL = URL(fileURLWithPath: "/BenchmarkDir\(ruleCount - 1)/file.pdf")
let fallbackURL = URL(fileURLWithPath: "/Other/file.pdf")

func stats(_ label: String, _ values: [Double]) {
    let sorted = values.sorted()
    let p95 = sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
    print(String(format: "%@: mean %.4f ms, median %.4f ms, P95 %.4f ms, max %.4f ms (n=%d)",
                 label, values.reduce(0, +) / Double(values.count), sorted[sorted.count / 2], p95, sorted.last!, sorted.count))
}
func measure(_ url: URL, expected: RoutingDecision, iterations: Int) -> [Double] {
    (0..<iterations).map { _ in
        let start = ProcessInfo.processInfo.systemUptime
        let result = engine.resolveDecision(for: url)
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        precondition(result == expected, "Benchmark 路由不正确，不能把错误分支当作性能结果")
        return elapsed
    }
}

print("规则数: \(ruleCount)，初始化: \(String(format: "%.3f", initialization)) ms")
stats("首次匹配（含首次类型查询）", measure(matchedURL, expected: .rule(target), iterations: 1))
for _ in 0..<100 { precondition(engine.resolveDecision(for: matchedURL) == .rule(target)) }
stats("热匹配最后一条规则", measure(matchedURL, expected: .rule(target), iterations: iterations))
stats("热 fallback", measure(fallbackURL, expected: .fallback(target), iterations: iterations))

final class BenchmarkOpener: FileOpening {
    func open(_ urls: [URL], withApplicationAt appURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        precondition(!urls.isEmpty && appURL.pathExtension == "app")
        completion(.success(()))
    }
}
if args.contains("--pipeline") {
    let coordinator = OpenRequestCoordinator(
        engine: engine,
        resolver: ApplicationResolver(locator: WorkspaceAppLocator(), ownBundleIdentifier: "com.example.OpenBy"),
        opening: WorkspaceOpening(opener: BenchmarkOpener()), openByBundleID: "com.example.OpenBy"
    )
    var samples: [Double] = []
    for n in 0...iterations {
        coordinator.handle(urls: [n.isMultiple(of: 2) ? matchedURL : fallbackURL])
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while coordinator.isBusy && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.0001) }
        precondition(!coordinator.isBusy && coordinator.recentErrors.isEmpty, "Pipeline 未正确完成")
        let sample = coordinator.recentMeasurements.last!
        precondition(sample.status == "系统已确认")
        if n == 0 { stats("首次转发（含真实应用定位；假打开）", [sample.dispatchMilliseconds!]) }
        else { samples.append(sample.dispatchMilliseconds!) }
    }
    stats("热转发（真实应用定位缓存；假打开）", samples)
}
