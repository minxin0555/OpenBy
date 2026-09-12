// swift-tools-version:6.0
import PackageDescription
import Foundation

let package = Package(
    name: "OpenBy",
    platforms: [.macOS(.v14)],
    targets: [
        // 库：全部业务逻辑（Core/System/Storage/UI）。做成库是为了让无 XCTest 环境下
        // 的 CLI 测试运行器（OpenByTestRunner）和基准（OpenByBenchmark）能 import 它。
        .target(
            name: "OpenBy",
            swiftSettings: [
                // AppKit 在本 SDK 中大量标注 @MainActor。v5 宽松并发 + 在
                // UI 上显式标注 @MainActor；路由状态交由独立串行队列管理。
                .swiftLanguageMode(.v5)
            ]
        ),
        // 应用可执行文件：唯一职责是拉起 NSApplication（main.swift 不允许出现在库 target）。
        .executableTarget(
            name: "OpenByApp",
            dependencies: ["OpenBy"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

// 本地保留测试源码时启用对应目标；公开源码无需这些目录即可构建。
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
for (name, path) in [
    ("OpenByTestRunner", "Sources/OpenByTestRunner"),
    ("OpenByBenchmark", "Benchmarks/OpenByBenchmark"),
] {
    if FileManager.default.fileExists(atPath: packageDirectory.appendingPathComponent(path).path) {
        package.targets.append(.executableTarget(
            name: name,
            dependencies: ["OpenBy"],
            path: path,
            swiftSettings: [.swiftLanguageMode(.v5)]
        ))
    }
}
