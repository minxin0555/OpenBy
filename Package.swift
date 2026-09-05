// swift-tools-version:6.0
import PackageDescription

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
                // Coordinator/UI 上显式标注 @MainActor，形成"主线程=整个 app"的模型。
                .swiftLanguageMode(.v5)
            ]
        ),
        // 应用可执行文件：唯一职责是拉起 NSApplication（main.swift 不允许出现在库 target）。
        .executableTarget(
            name: "OpenByApp",
            dependencies: ["OpenBy"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 无 Xcode/CLT 环境下 `swift test` 不可用（CLT SDK 不含 XCTest，Swift Testing
        // framework 也不在可链接路径）。用轻量断言运行器替代，`swift run OpenByTestRunner`。
        .executableTarget(
            name: "OpenByTestRunner",
            dependencies: ["OpenBy"],
            path: "Sources/OpenByTestRunner",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "OpenByBenchmark",
            dependencies: ["OpenBy"],
            path: "Benchmarks/OpenByBenchmark",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
