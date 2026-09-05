import AppKit

/// 库的公开启动入口。`Sources/OpenByApp/main.swift` 只调用这一个函数。
public func openByMain() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // 路由启动全程 .accessory，避免 Dock 图标常驻和前台闪窗；
    // 打开设置窗口时由 AppDelegate 临时提升为 .regular。
    app.setActivationPolicy(.accessory)
    app.run()
}
