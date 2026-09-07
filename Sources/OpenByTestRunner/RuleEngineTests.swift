import Foundation
import OpenBy
import UniformTypeIdentifiers

enum RuleEngineTests {
    static let pdfTypeID = UTType.pdf.identifier
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
        // 测试运行器没有完整 Launch Services 数据库时，按扩展名创建的 PDF UTI
        // 可能是临时 dyn.* 标识。生产配置本来也会保存扩展名，测试保持同样语义。
        let displayExtensions = extensions.isEmpty && type == pdfTypeID ? ["pdf"] : extensions
        return FileHandler(
            contentTypeIdentifier: type,
            fallbackApplication: fallback,
            displayExtensions: displayExtensions,
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
                handler(pdfTypeID, rules: [
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
                handler(pdfTypeID, rules: [rule(folder: "/A/One", target: appA)]),
            ])
            let engine = RuleEngine(configuration: config)
            let url = URL(fileURLWithPath: "/Elsewhere/x.pdf")
            try expectEqual(engine.resolveDecision(for: url), .fallback(fallback))
        }),

        // MARK: 禁用项
        MiniTest.Case("禁用规则被忽略", {
            let config = Configuration(schemaVersion: 1, handlers: [
                handler(pdfTypeID, rules: [
                    rule(folder: "/A", target: appA, enabled: false),
                    rule(folder: "/A", target: appB),
                ]),
            ])
            let engine = RuleEngine(configuration: config)
            try expectEqual(engine.resolveDecision(for: URL(fileURLWithPath: "/A/x.pdf")), .rule(appB))
        }),
        MiniTest.Case("禁用 handler 被忽略 → none", {
            let config = Configuration(schemaVersion: 1, handlers: [
                handler(pdfTypeID, enabled: false),
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
        MiniTest.Case("PDF 文件类型匹配", {
            let config = Configuration(schemaVersion: 1, handlers: [handler(pdfTypeID)])
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
            let config = Configuration(schemaVersion: 1, handlers: [handler(pdfTypeID)])
            let engine = RuleEngine(configuration: config)
            let fb = try expectNotNil(engine.fallbackApplication(for: URL(fileURLWithPath: "/A/x.pdf")))
            try expectEqual(fb.bundleIdentifier, "com.example.Fallback")
        }),

        MiniTest.Case("类型缓存保留通用 handler 优先级", {
            let engine = RuleEngine(configuration: Configuration(schemaVersion: 1, handlers: [
                handler("public.data", fallback: appA), handler(pdfTypeID, fallback: appB)
            ]))
            for ext in ["pdf", "PDF", "pdf"] {
                try expectEqual(engine.resolveDecision(for: URL(fileURLWithPath: "/Other/file.\(ext)")), .fallback(appA))
            }
        }),
        MiniTest.Case("PDF、图片、文本和 Office 独立缓存且新配置不复用旧结果", {
            let extensions = ["pdf", "png", "jpeg", "txt", "docx"]
            let handlers = extensions.enumerated().map { index, ext in
                handler(UTType(filenameExtension: ext)!.identifier, extensions: [ext],
                        rules: [rule(folder: "/Special", target: appB)],
                        fallback: ApplicationReference(bundleIdentifier: "com.test.Type\(index)", displayName: ext))
            }
            let engine = RuleEngine(configuration: Configuration(schemaVersion: 1, handlers: handlers))
            for _ in 0..<3 {
                for (index, ext) in extensions.enumerated() {
                    try expectEqual(engine.resolveDecision(for: URL(fileURLWithPath: "/Special/file.\(ext.uppercased())")), .rule(appB))
                    try expectEqual(engine.resolveDecision(for: URL(fileURLWithPath: "/Other/file.\(ext)")), .fallback(handlers[index].fallbackApplication))
                }
            }
            let empty = RuleEngine(configuration: Configuration(schemaVersion: 1, handlers: []))
            try expectEqual(empty.resolveDecision(for: URL(fileURLWithPath: "/Special/file.pdf")), .none)
        }),

        // MARK: 多文件分组
        MiniTest.Case("批量文件按目标分组", {
            let config = Configuration(schemaVersion: 1, handlers: [
                handler(pdfTypeID, rules: [rule(folder: "/Docs", target: appA)]),
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
