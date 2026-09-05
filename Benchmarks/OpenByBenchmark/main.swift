import Foundation
import OpenBy

// 路由基准：测量单文件在 N 条规则下的一次匹配耗时。
// 用法: swift run -c release OpenByBenchmark --rules 10000 --iterations 2000
var ruleCount = 1000
var iterations = 1000

var args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    switch args[i] {
    case "--rules":
        if i + 1 < args.count { ruleCount = Int(args[i + 1]) ?? ruleCount; i += 1 }
    case "--iterations":
        if i + 1 < args.count { iterations = Int(args[i + 1]) ?? iterations; i += 1 }
    default:
        break
    }
    i += 1
}

// 构造 N 条互不重叠的规则（按顺序扫描，最坏情况命中最后一条）。
var rules: [FolderRule] = []
for n in 0..<ruleCount {
    rules.append(FolderRule(
        folderPath: "/BenchmarkDir\(n)",
        includesDescendants: true,
        targetApplication: ApplicationReference(bundleIdentifier: "com.example.App\(n)", displayName: "App\(n)")
    ))
}
let config = Configuration(schemaVersion: 1, handlers: [
    FileHandler(
        contentTypeIdentifier: "com.adobe.pdf",
        fallbackApplication: ApplicationReference(bundleIdentifier: "com.apple.Preview", displayName: "Preview"),
        rules: rules
    ),
])
let engine = RuleEngine(configuration: config)
let worstCaseURL = URL(fileURLWithPath: "/BenchmarkDir\(ruleCount - 1)/file.pdf")

// 预热（首调涉及 UTI 查表）。
for _ in 0..<100 { _ = engine.resolveDecision(for: worstCaseURL) }

let start = CFAbsoluteTimeGetCurrent()
for _ in 0..<iterations {
    _ = engine.resolveDecision(for: worstCaseURL)
}
let elapsed = CFAbsoluteTimeGetCurrent() - start
let perRouteMs = elapsed / Double(iterations) * 1000

print("规则数: \(ruleCount), 迭代: \(iterations)")
print(String(format: "单次路由: %.4f ms", perRouteMs))
print(String(format: "总耗时: %.3f s", elapsed))
