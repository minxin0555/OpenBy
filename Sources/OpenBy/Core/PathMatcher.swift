import Foundation

/// 纯路径判定：判断文件是否位于某文件夹内。
///
/// 设计约束（对应文档第 7 节）：
/// - 组件级比较，天然避免 `/A/Paper` 误匹配 `/A/Papers2/file.pdf`。
/// - 只做 `.`/`..` 与尾部斜杠的标准化，**绝不**解析符号链接。
/// - 大小写不敏感（APFS 默认行为），比较前统一 NFC 规范形式。
///
/// 性能：规则目录组件在 `RuleEngine` 初始化时预计算，文件路径每个文件只标准化一次
/// （文档第 9 节"配置保存时预编译/标准化规则"）。
public enum PathMatcher {
    /// 判断文件路径是否位于规则目录内（自动标准化两侧）。
    public static func isPath(_ filePath: String, insideFolder folderPath: String, includesDescendants: Bool) -> Bool {
        isPath(
            normalizedComponents(of: filePath),
            insideFolder: normalizedComponents(of: folderPath),
            includesDescendants: includesDescendants
        )
    }

    /// 判断文件路径是否位于规则目录内（两侧均已标准化——路由热路径用）。
    public static func isPath(_ fileComponents: [String], insideFolder folderComponents: [String], includesDescendants: Bool) -> Bool {
        guard !folderComponents.isEmpty, folderComponents.count <= fileComponents.count else { return false }

        // 组件级前缀比较。
        for i in 0..<folderComponents.count {
            if fileComponents[i] != folderComponents[i] { return false }
        }

        if includesDescendants {
            // 任意深度子项，含文件夹自身。
            return true
        }
        // 仅直接子文件：文件组件数 = 目录组件数 + 1。
        return fileComponents.count == folderComponents.count + 1
    }

    /// URL 便捷入口。
    public static func isFile(_ fileURL: URL, insideFolder folderPath: String, includesDescendants: Bool) -> Bool {
        isPath(fileURL.path, insideFolder: folderPath, includesDescendants: includesDescendants)
    }

    /// 标准化路径为比较用组件：消去 `.`/`..` 与尾部斜杠，NFC + 小写。
    /// 不解符号链接、不访问文件系统。
    public static func normalizedComponents(of path: String) -> [String] {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        return components.map { $0.precomposedStringWithCanonicalMapping.lowercased() }
    }
}
