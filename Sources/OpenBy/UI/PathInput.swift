import Foundation

/// 用户输入的路径规范化。
public enum PathInput {
    /// 展开 `~` 前缀并标准化为绝对路径；不做符号链接解析。
    public static func expandedAbsolutePath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return (path as NSString).expandingTildeInPath
        }
        return path
    }
}
