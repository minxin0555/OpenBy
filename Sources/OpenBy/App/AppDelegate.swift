import AppKit

/// 应用委托：只做生命周期与文件打开事件的接收，把 URL 立即交给 OpenRequestCoordinator。
/// 不做任何规则匹配、打开或 I/O（对应文档 4.3：设置窗口、图标扫描都不能阻塞这条路径）。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: OpenRequestCoordinator?
    private var settingsController: SettingsWindowController?
    /// applicationDidFinishLaunching 之前到达的 open 事件先缓冲。
    private var pendingURLs: [URL] = []
    /// 已显式以"路由启动"被调用（收到过文件），避免与普通启动抢窗口。
    private var didRouteFiles = false

    /// 与设置窗口共享的实例：同一套配置存储 / 应用解析 / 默认关联服务。
    private var store: ConfigurationStore?
    private var resolver: ApplicationResolver?
    private var associationService: AssociationService?

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ConfigurationStore(fileURL: ConfigurationStore.defaultFileURL())
        let configuration = store.load()
        let engine = RuleEngine(configuration: configuration)
        let resolver = ApplicationResolver(
            locator: WorkspaceAppLocator(),
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        )
        let associationService = AssociationService(provider: WorkspaceDefaultAppProvider())
        let opening = WorkspaceOpening(opener: WorkspaceFileOpening())

        self.store = store
        self.resolver = resolver
        self.associationService = associationService

        let coordinator = OpenRequestCoordinator(
            engine: engine,
            resolver: resolver,
            opening: opening,
            openByBundleID: Bundle.main.bundleIdentifier
        )
        coordinator.shouldTerminateIfIdle = { [weak self] in
            !(self?.settingsController?.window?.isVisible ?? false)
        }
        self.coordinator = coordinator

        // 调试便利：`swift run OpenByApp file.pdf` 直接把文件路径当参数传入。
        // 正常 Finder/`open` 流程走 application(_:open:)。
        let fileArgs = CommandLine.arguments.dropFirst()
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }

        if !pendingURLs.isEmpty || !fileArgs.isEmpty {
            didRouteFiles = true
            coordinator.handle(urls: pendingURLs + fileArgs)
            pendingURLs.removeAll()
        } else {
            // 普通启动（双击应用）：稍候无文件则打开设置窗口。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, !self.didRouteFiles, self.pendingURLs.isEmpty else { return }
                self.showSettingsWindow()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        didRouteFiles = true
        if let coordinator {
            coordinator.handle(urls: urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 关闭设置窗口：有在途请求时延后退出（协调器会在完成后重新 terminate）。
        !(coordinator?.isBusy ?? false)
    }

    // MARK: - 设置窗口

    @MainActor
    @discardableResult
    private func showSettingsWindow() -> Bool {
        let controller: SettingsWindowController
        if let existing = settingsController {
            controller = existing
        } else {
            guard let store, let resolver, let associationService, let coordinator else { return false }
            let model = SettingsModel(
                store: store,
                resolver: resolver,
                associationService: associationService,
                openByBundleID: Bundle.main.bundleIdentifier,
                onConfigurationChanged: { [weak coordinator] in
                    coordinator?.reload(configuration: store.snapshot())
                }
            )
            controller = SettingsWindowController(
                model: model,
                recentErrorsProvider: { [weak self] in self?.coordinator?.recentErrors ?? [] }
            )
            settingsController = controller
        }
        controller.show()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
