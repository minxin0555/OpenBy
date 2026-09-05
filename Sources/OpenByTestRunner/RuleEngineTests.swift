import Foundation
import OpenBy

enum RuleEngineTests {
    static let appA = ApplicationReference(bundleIdentifier: "com.example.AppA", displayName: "AppA")
    static let appB = ApplicationReference(bundleIdentifier: "com.example.AppB", displayName: "AppB")
    static let fallback = ApplicationReference(bundleIdentifier: "com.example.Fallback", displayName: "Fallback")

    static func handler(
        _ type: String,
        extensions: [String] = [],
        rules: [FolderRule] = [],
        fallback: ApplicationReference = fallback,
        enabled: Bool = true
    ) -> FileHandler {
        FileHandler(
            contentTypeIdentifier: type,
            fallbackApplication: fallback,
            displayExtensions: extensions,
            enabled: enabled,
            rules: rules
        )
    }

    static func rule(folder: String, target: ApplicationReference, descendants: Bool = true, enabled: Bool = true) -> FolderRule {
        FolderRule(enabled: enabled, folderPath: folder, includesDescendants: descendants, targetApplication: target)
    }

    static let cases: [MiniTest.Case] = [
        // MARK: 规则顺序
        MiniTest.Case("first-match-wins：第一条命中生效", {
            let config = Configuration(schemaVersion: 1, handlers: [
                handler("com.adobe.pdf", rules: [
                    rule(folder: "/A", target: appA),
                    rule(folder: "/A/B", target: appB),
                ]),
            ])
            let engine = RuleEngine(configuration: config)
            let url = URL(fileURLWithPath: "/A/B/x.pdf")
            try expectEqual(engine.resolveDecision(for: url), .rule(appA))
        }),

        // MARK: fallback
        MiniTest.Case("未命中任何规则 → fallback", {
            let config = Configuration(schemaVersion: 1, handlers: [
                handler("com.adobe.pdf", rules: [rule(folder: "/A/One", target: appA)]),
            ])
            let engine = RuleEngine(configuration: config)
            let url = URL(fileURLWithPath: "/Elsewhere/x.pdf")
            try expectEqual(engine.resolveDecision(for: url), .fallback(fallback))
        }),

        // MARK: 禁用项
        MiniTest.Case("禁用规则被忽略", {
            let config = Configuration(schemaVersion: 1, handlers: [
                handler("com.adobe.pdf", rules: [
                    rule(folder: "/A", target: appA, enabled: false),
                    rule(folder: "/A", target: appB),
                ]),
            ])
            let engine = RuleEngine(configuration: config)
            try expectEqual(engine.resolveDecision(for: URL(fileURLWithPath: "/A/x.pdf")), .rule(appB))
        }),
        MiniTest.Case("禁用 handler 被忽略 → none", {
            let config = Configuration(schemaVersion: 1, handlers: [
                handler("com.adobe.pdf", enabled: false),
            ])
            let engine = RuleEngine(configuration: config)
            try expectEqual(engine.resolveDecision(for: URL(fileURLWithPath: "/A/x.pdf")), .none)
        }),

        // MARK: 空配置安全
        MiniTest.Case("空配置 → none", {
            let engine = RuleEngine(configuration: Configuration(schemaVersion: 1, handlers: []))
            try expectEqual(engine.resolveDecision(for: URL(fileURLWithPath: "/A/x.pdf")), .none)
        }),

        // MARK: UTI 匹配
        MiniTest.Case("UTI 精确匹配", {
            let config = Configuration(schemaVersion: 1, handlers: [handler("com.adobe.pdf")])
            let engine = RuleEngine(configuration: config)
            try expectEqual(engine.resolveDecision(for: URL(fileURLWithPath: "/A/x.pdf")), .fallback(fallback))
        }),
        MiniTest.Case("UTI conformance：public.data 祖先类型", {
            let config = Configuration(schemaVersion: 1, handlers: [handler("public.data")])
            let engine = RuleEngine(configuration: config)
            // pdf 符合 public.data → 命中
            try expectEqual(engine.resolveDecision(for: URL(fileURLWithPath: "/A/x.pdf")), .fallback(fallback))
        }),
        MiniTest.Case("扩展名兜底匹配（无系统 UTI 的未知扩展名）", {
            let config = Configuration(schemaVersion: 1, handlers: [
                handler("com.example.mystery", extensions: ["openbymrk"]),
            ])
            let engine = RuleEngine(configuration: config)
            try expectEqual(engine.resolveDecision(for: URL(fileURLWithPath: "/A/x.openbymrk")), .fallback(fallback))
        }),

        // MARK: fallbackApplication(for:)
        MiniTest.Case("fallbackApplication(for:) 返回所属 handler 的回退应用", {
            let config = Configuration(schemaVersion: 1, handlers: [handler("com.adobe.pdf")])
            let engine = RuleEngine(configuration: config)
            let fb = try expectNotNil(engine.fallbackApplication(for: URL(fileURLWithPath: "/A/x.pdf")))
            try expectEqual(fb.bundleIdentifier, "com.example.Fallback")
        }),

        // MARK: 多文件分组
        MiniTest.Case("批量文件按目标分组", {
            let config = Configuration(schemaVersion: 1, handlers: [
                handler("com.adobe.pdf", rules: [rule(folder: "/Docs", target: appA)]),
            ])
            let engine = RuleEngine(configuration: config)
            let inDocs = URL(fileURLWithPath: "/Docs/a.pdf")
            let outside = URL(fileURLWithPath: "/Other/b.pdf")
            let result = BatchRouter.group([inDocs, outside], engine: engine)

            try expectEqual(result.unrouted.count, 0)
            try expectEqual(result.groups.count, 2)
            let targets = result.groups.map(\.target.bundleIdentifier).sorted()
            try expectEqual(targets, ["com.example.AppA", "com.example.Fallback"])
        }),
        MiniTest.Case("无法路由的文件进 unrouted", {
            let engine = RuleEngine(configuration: Configuration(schemaVersion: 1, handlers: []))
            let url = URL(fileURLWithPath: "/Docs/x.openbymrk")
            let result = BatchRouter.group([url], engine: engine)
            try expectEqual(result.groups.count, 0)
            try expectEqual(result.unrouted.count, 1)
        }),
    ]
}
