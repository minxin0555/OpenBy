import Foundation
import OpenBy

enum PathMatcherTests {
    static let cases: [MiniTest.Case] = [
        // MARK: 文件夹本身
        MiniTest.Case("文件夹本身命中（包含子项模式）", {
            try check(PathMatcher.isPath("/A/Paper", insideFolder: "/A/Paper", includesDescendants: true))
        }),
        MiniTest.Case("文件夹本身不命中直接子项模式", {
            try check(!PathMatcher.isPath("/A/Paper", insideFolder: "/A/Paper", includesDescendants: false))
        }),

        // MARK: 直接子项 / 多级子项
        MiniTest.Case("直接子文件命中", {
            try check(PathMatcher.isPath("/A/Paper/a.pdf", insideFolder: "/A/Paper", includesDescendants: false))
        }),
        MiniTest.Case("多级子文件不命中直接子项模式", {
            try check(!PathMatcher.isPath("/A/Paper/sub/a.pdf", insideFolder: "/A/Paper", includesDescendants: false))
        }),
        MiniTest.Case("多级子文件命中包含子项模式", {
            try check(PathMatcher.isPath("/A/Paper/sub/deep/a.pdf", insideFolder: "/A/Paper", includesDescendants: true))
        }),

        // MARK: 相似目录名边界
        MiniTest.Case("Paper 不匹配 Papers2", {
            try check(!PathMatcher.isPath("/A/Papers2/file.pdf", insideFolder: "/A/Paper", includesDescendants: true))
        }),
        MiniTest.Case("Paper 匹配 Paper 下的文件", {
            try check(PathMatcher.isPath("/A/Paper/file.pdf", insideFolder: "/A/Paper", includesDescendants: true))
        }),

        // MARK: 中文 / 空格 / emoji / Unicode
        MiniTest.Case("中文目录", {
            try check(PathMatcher.isPath("/Users/t/文献/论文.pdf", insideFolder: "/Users/t/文献", includesDescendants: true))
        }),
        MiniTest.Case("含空格目录", {
            try check(PathMatcher.isPath("/Users/t/My Documents/a.pdf", insideFolder: "/Users/t/My Documents", includesDescendants: true))
        }),
        MiniTest.Case("emoji 目录", {
            try check(PathMatcher.isPath("/Users/t/📁 资料/a.pdf", insideFolder: "/Users/t/📁 资料", includesDescendants: true))
        }),
        MiniTest.Case("NFC/NFD 组合字符等价", {
            let composed = "/Users/t/café/a.pdf"          // é = U+00E9
            let decomposed = "/Users/t/cafe\u{0301}/a.pdf" // é = e + U+0301
            try check(PathMatcher.isPath(decomposed, insideFolder: composed, includesDescendants: true))
            try check(PathMatcher.isPath(composed, insideFolder: decomposed, includesDescendants: true))
        }),

        // MARK: 路径标准化
        MiniTest.Case("点目录标准化", {
            try check(PathMatcher.isPath("/A/./Paper/../Paper/a.pdf", insideFolder: "/A/Paper", includesDescendants: true))
        }),
        MiniTest.Case("尾部斜杠", {
            try check(PathMatcher.isPath("/A/Paper/a.pdf", insideFolder: "/A/Paper/", includesDescendants: false))
        }),

        // MARK: 大小写
        MiniTest.Case("大小写不敏感（APFS 默认行为）", {
            try check(PathMatcher.isPath("/A/paper/a.pdf", insideFolder: "/A/Paper", includesDescendants: true))
        }),

        // MARK: 符号链接字面匹配（不解析）
        MiniTest.Case("符号链接路径按字面匹配", {
            // 规则目录 /A/Paper 与文件 /real/Place/a.pdf 无关；即便 a.pdf 是符号链接指向别处，
            // v1 语义按 URL 字面路径判定，不做 resolvingSymlinksInPath。
            try check(!PathMatcher.isPath("/real/Place/a.pdf", insideFolder: "/A/Paper", includesDescendants: true))
        }),

        // MARK: URL 便捷入口
        MiniTest.Case("URL 便捷入口", {
            let url = URL(fileURLWithPath: "/A/Paper/a.pdf")
            try check(PathMatcher.isFile(url, insideFolder: "/A/Paper", includesDescendants: true))
        }),
    ]
}
