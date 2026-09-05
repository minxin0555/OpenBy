import AppKit

/// 设置窗口：三个页签（文件类型 / 规则 / 诊断）。持有共享的 SettingsModel。
final class SettingsWindowController: NSWindowController, NSTabViewDelegate {
    private let model: SettingsModel
    private let handlersVC: HandlersViewController
    private let rulesVC: RulesViewController
    private let diagnosticsVC: DiagnosticsViewController
    private let tabView = NSTabView()
    private var tabItems: [NSTabViewItem] = []
    private var didBuildContent = false

    init(
        model: SettingsModel,
        recentErrorsProvider: @escaping () -> [String]
    ) {
        self.model = model
        self.handlersVC = HandlersViewController(model: model)
        self.rulesVC = RulesViewController(model: model)
        self.diagnosticsVC = DiagnosticsViewController(model: model, recentErrorsProvider: recentErrorsProvider)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenBy 设置"
        window.minSize = NSSize(width: 620, height: 420)
        window.center()
        super.init(window: window)

        // 文件类型列表双击 → 切到规则页并聚焦该类型。
        handlersVC.onSelectHandler = { [weak self] handler in
            guard let self else { return }
            self.rulesVC.focus(handlerID: handler.id)
            if let rulesTab = self.tabItems.first(where: { $0.identifier as? String == "rules" }) {
                self.tabView.selectTabViewItem(rulesTab)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    // MARK: - 展示

    func show() {
        if !didBuildContent {
            buildContent()
            didBuildContent = true
        }
        showWindow(nil)
    }

    /// 配置变更后刷新各页。
    func reloadFromModel() {
        handlersVC.reload()
        rulesVC.reload()
        diagnosticsVC.reload()
    }

    private func buildContent() {
        tabView.delegate = self

        let handlersTab = NSTabViewItem(identifier: "handlers")
        handlersTab.label = "文件类型"
        handlersTab.view = handlersVC.view
        tabItems.append(handlersTab)

        let rulesTab = NSTabViewItem(identifier: "rules")
        rulesTab.label = "规则"
        rulesTab.view = rulesVC.view
        tabItems.append(rulesTab)

        let diagnosticsTab = NSTabViewItem(identifier: "diagnostics")
        diagnosticsTab.label = "诊断"
        diagnosticsTab.view = diagnosticsVC.view
        tabItems.append(diagnosticsTab)

        for item in tabItems {
            tabView.addTabViewItem(item)
        }

        tabView.translatesAutoresizingMaskIntoConstraints = false
        window?.contentView = tabView

        if let contentView = window?.contentView {
            NSLayoutConstraint.activate([
                tabView.topAnchor.constraint(equalTo: contentView.topAnchor),
                tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
        }
    }
}
