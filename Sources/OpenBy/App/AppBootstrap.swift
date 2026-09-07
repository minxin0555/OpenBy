import AppKit

/// 库的公开启动入口。`Sources/OpenByApp/main.swift` 只调用这一个函数。
@MainActor
public func openByMain() {
    let startedAt = ProcessInfo.processInfo.systemUptime
    let app = NSApplication.shared
    let delegate = AppDelegate(startedAt: startedAt)
    app.delegate = delegate
    // 单进程后台常驻，菜单栏和设置窗口共用同一服务，不占 Dock。
    app.setActivationPolicy(.accessory)
    // NSApplication 的 delegate 引用不负责所有权，确保整个常驻周期都保留委托。
    withExtendedLifetime(delegate) { app.run() }
}
