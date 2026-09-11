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
        installApplicationMenu()
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
        item.menu = menu
        statusItem = item
        rebuildStatusMenu(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        rebuildStatusMenu(menu)
        let status = SMAppService.mainApp.status
        loginItem?.state = status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)
        loginItem?.title = status == .requiresApproval ? "登录时启动（等待系统允许）…" : "登录时启动"
    }

    private func installApplicationMenu() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            item.submenu = menu
            main.addItem(item)
            return menu
        }
        func command(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String,
                     target: AnyObject? = nil, modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            item.keyEquivalentModifierMask = modifiers
            menu.addItem(item)
        }
        let application = submenu("OpenBy")
        command(application, "关于 OpenBy", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "", target: NSApp)
        command(application, "设置…", #selector(openSettings), ",", target: self)
        application.addItem(.separator())
        command(application, "隐藏 OpenBy", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        command(application, "隐藏其他", #selector(NSApplication.hideOtherApplications(_:)), "h", target: NSApp, modifiers: [.command, .option])
        command(application, "全部显示", #selector(NSApplication.unhideAllApplications(_:)), "", target: NSApp)
        application.addItem(.separator())
        command(application, "退出 OpenBy", #selector(quit), "q", target: self)
        let file = submenu("文件")
        command(file, "关闭窗口", #selector(NSWindow.performClose(_:)), "w")
        let edit = submenu("编辑")
        command(edit, "撤销", Selector(("undo:")), "z")
        command(edit, "重做", Selector(("redo:")), "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        command(edit, "剪切", #selector(NSText.cut(_:)), "x")
        command(edit, "复制", #selector(NSText.copy(_:)), "c")
        command(edit, "粘贴", #selector(NSText.paste(_:)), "v")
        command(edit, "全选", #selector(NSText.selectAll(_:)), "a")
        let window = submenu("窗口")
        command(window, "最小化", #selector(NSWindow.performMiniaturize(_:)), "m")
        command(window, "缩放", #selector(NSWindow.performZoom(_:)), "")
        command(window, "显示设置窗口", #selector(openSettings), "", target: self)
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let handlers = store?.snapshot().handlers ?? []
        let font = NSFont.menuFont(ofSize: 0)
        let nameWidth = handlers.map {
            (SettingsModel.typeDisplayName($0) as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: max(220, nameWidth + 90))]
        if handlers.isEmpty {
            menu.addItem(NSMenuItem(title: "尚无文件类型", action: nil, keyEquivalent: ""))
        }
        for handler in handlers {
            let types = handler.contentTypes
            let managed = types.filter {
                associationService?.isManagedByOpenBy(contentType: $0, openByBundleID: Bundle.main.bundleIdentifier ?? "") == true
            }.count
            let enabled = handler.enabled && managed > 0
            let status = enabled ? "已启用" : "已停用"
            let name = SettingsModel.typeDisplayName(handler)
            let entry = NSMenuItem(title: "\(name)\t\(status)", action: #selector(openHandlerSettings(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = handler.id
            let title = NSMutableAttributedString(string: "\(name)\t", attributes: [
                .font: font, .paragraphStyle: paragraph,
            ])
            title.append(NSAttributedString(string: status, attributes: [
                .font: font, .paragraphStyle: paragraph,
                .foregroundColor: enabled ? NSColor.systemGreen : NSColor.systemRed,
            ]))
            entry.attributedTitle = title
            entry.toolTip = "\(name)：系统接管 \(managed)/\(types.count) 个类型。点击打开设置。"
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let login = NSMenuItem(title: "登录时启动", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        loginItem = login
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 OpenBy", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
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

    @objc private func openHandlerSettings(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, showSettingsWindow() else { return }
        settingsController?.focus(handlerID: id)
    }

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
