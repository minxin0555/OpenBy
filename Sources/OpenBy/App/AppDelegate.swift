import AppKit
import ServiceManagement
import Carbon

/// 常驻应用入口：主线程只接收事件与管理 UI，配置加载和路由均在后台完成。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var coordinator: OpenRequestCoordinator?
    private var settingsController: SettingsWindowController?
    private var pendingRequests: [(urls: [URL], receivedAt: TimeInterval)] = []
    private var didRouteFiles = false
    private var wantsSettings = false
    private var isLoginLaunch = false
    private var statusItem: NSStatusItem?
    private var loginItem: NSMenuItem?
    private var workspaceObservers: [NSObjectProtocol] = []
    private let startedAt: TimeInterval
    private var store: ConfigurationStore?
    private var resolver: ApplicationResolver?
    private var associationService: AssociationService?

    init(startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.startedAt = startedAt
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        isLoginLaunch = event?.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
            || event?.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsServiceItem)) != nil
            || CommandLine.arguments.contains("--background")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        let bundleID = Bundle.main.bundleIdentifier
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        DispatchQueue.global(qos: .userInitiated).async {
            let store = ConfigurationStore(fileURL: ConfigurationStore.defaultFileURL())
            let engine = RuleEngine(configuration: store.load())
            let resolver = ApplicationResolver(locator: WorkspaceAppLocator(), ownBundleIdentifier: bundleID)
            let coordinator = OpenRequestCoordinator(
                engine: engine, resolver: resolver,
                opening: WorkspaceOpening(opener: WorkspaceFileOpening()), openByBundleID: bundleID
            )
            let fileArgs = args.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
            DispatchQueue.main.async {
                self.store = store
                self.resolver = resolver
                self.associationService = AssociationService(provider: WorkspaceDefaultAppProvider())
                self.coordinator = coordinator
                self.observeWorkspace()
                if !fileArgs.isEmpty {
                    self.didRouteFiles = true
                    self.pendingRequests.append((fileArgs, self.startedAt))
                }
                for request in self.pendingRequests {
                    coordinator.handle(urls: request.urls, receivedAt: request.receivedAt)
                }
                self.pendingRequests.removeAll()
                if self.wantsSettings {
                    self.showSettingsWindow()
                } else if !self.didRouteFiles && !self.isLoginLaunch {
                    // 仅等待启动文件事件，不延迟已经收到的打开请求。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if !self.didRouteFiles { self.showSettingsWindow() }
                    }
                }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        didRouteFiles = true
        let receivedAt = ProcessInfo.processInfo.systemUptime
        if let coordinator { coordinator.handle(urls: urls, receivedAt: receivedAt) }
        else { pendingRequests.append((urls, receivedAt)) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menuIcon = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "OpenBy")
        menuIcon?.size = NSSize(width: 18, height: 18)
        menuIcon?.isTemplate = true
        menuIcon?.accessibilityDescription = "OpenBy"
        item.button?.image = menuIcon
        item.button?.toolTip = "OpenBy · 后台自动打开"
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "OpenBy 正在后台运行", action: nil, keyEquivalent: "")
        menu.addItem(title)
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let login = NSMenuItem(title: "登录时启动", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        menu.addItem(login)
        loginItem = login
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 OpenBy", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let status = SMAppService.mainApp.status
        loginItem?.state = status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)
        loginItem?.title = status == .requiresApproval ? "登录时启动（等待系统允许）…" : "登录时启动"
    }

    @objc private func toggleLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更改登录启动设置"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func openSettings() { showSettingsWindow() }

    @objc private func quit() {
        if coordinator?.isBusy == true || !pendingRequests.isEmpty {
            let alert = NSAlert()
            alert.messageText = "仍有文件正在转交"
            alert.informativeText = "现在退出会停止尚未转交的请求。"
            alert.addButton(withTitle: "继续运行")
            alert.addButton(withTitle: "退出")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        NSApp.terminate(nil)
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.coordinator?.invalidateApplications() }
            })
        }
    }

    @discardableResult
    private func showSettingsWindow() -> Bool {
        guard let store, let resolver, let associationService, let coordinator else {
            wantsSettings = true
            return false
        }
        wantsSettings = false
        let controller: SettingsWindowController
        if let existing = settingsController { controller = existing }
        else {
            let model = SettingsModel(
                store: store, resolver: resolver, associationService: associationService,
                openByBundleID: Bundle.main.bundleIdentifier,
                onConfigurationChanged: { [weak coordinator] in coordinator?.reload(configuration: store.snapshot()) }
            )
            controller = SettingsWindowController(model: model)
            settingsController = controller
        }
        controller.show()
        // accessory 应用也可以拥有可交互窗口，无需切换 Dock 策略。
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
