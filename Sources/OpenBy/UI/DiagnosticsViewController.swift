import AppKit
import UniformTypeIdentifiers

/// 诊断：应用/配置路径、导出配置、逐文件类型自检（默认关联、目标应用、规则文件夹）、最近错误。
@MainActor
final class DiagnosticsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let model: SettingsModel
    private let recentErrorsProvider: () -> [String]

    private let infoLabel = NSTextField(labelWithString: "")
    private let exportButton = NSButton(title: "导出配置…", target: nil, action: nil)
    private let refreshButton = NSButton(title: "重新检查", target: nil, action: nil)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let performanceLabel = NSTextField(wrappingLabelWithString: "暂无打开记录")
    private var checkGeneration = 0
    private let errorsTitle = NSTextField(labelWithString: "需要留意的问题")
    private let errorsLabel = NSTextField(labelWithString: "没有发现问题")

    /// 自检结果行。
    private struct Row {
        let handlerName: String
        let takenOver: Bool
        let appsOK: Bool
        let foldersOK: Bool
    }
    private var rows: [Row] = []

    init(model: SettingsModel, recentErrorsProvider: @escaping () -> [String]) {
        self.model = model
        self.recentErrorsProvider = recentErrorsProvider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    override func loadView() {
        view = NSView()
        buildUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reload()
    }

    // MARK: - UI

    private func buildUI() {
        infoLabel.font = .systemFont(ofSize: 12)
        infoLabel.lineBreakMode = .byTruncatingMiddle
        infoLabel.maximumNumberOfLines = 0
        infoLabel.isSelectable = true
        performanceLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        performanceLabel.maximumNumberOfLines = 0
        performanceLabel.isSelectable = true
        performanceLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        errorsTitle.stringValue = "最近问题"
        errorsTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        errorsLabel.textColor = .secondaryLabelColor
        errorsLabel.font = .systemFont(ofSize: 12)
        errorsLabel.lineBreakMode = .byWordWrapping
        errorsLabel.maximumNumberOfLines = 0
        errorsLabel.isSelectable = true
        errorsLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        SettingsStyle.button(exportButton, symbol: "square.and.arrow.up")
        exportButton.target = self
        exportButton.action = #selector(exportConfig(_:))
        SettingsStyle.button(refreshButton, symbol: "arrow.clockwise")
        refreshButton.target = self
        refreshButton.action = #selector(reload(_:))

        for (id, title, width) in [("handler", "文件类型", 140.0), ("taken", "自动打开", 120.0), ("apps", "应用", 130.0), ("folders", "文件夹", 130.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.style = .inset
        tableView.rowHeight = 36
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .none
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.heightAnchor.constraint(equalToConstant: 180).isActive = true

        let header = SettingsStyle.row([SettingsStyle.label("帮助与诊断", size: 22, weight: .semibold), SettingsStyle.spacer(), exportButton, refreshButton])
        let content = SettingsStyle.column([
            header,
            SettingsStyle.column([SettingsStyle.label("应用信息", size: 14, weight: .semibold), SettingsStyle.group(infoLabel)], spacing: 10),
            SettingsStyle.column([SettingsStyle.label("状态检查", size: 14, weight: .semibold), SettingsStyle.group(scrollView, inset: 0)], spacing: 10),
            SettingsStyle.column([SettingsStyle.label("打开性能", size: 14, weight: .semibold), SettingsStyle.group(performanceLabel)], spacing: 10),
            SettingsStyle.column([errorsTitle, SettingsStyle.group(errorsLabel)], spacing: 10),
        ], spacing: 24)
        let page = SettingsFlippedView()
        let pageScroll = NSScrollView()
        pageScroll.documentView = page
        pageScroll.hasVerticalScroller = true
        pageScroll.autohidesScrollers = true
        pageScroll.drawsBackground = false
        for child in [pageScroll, page, content] { child.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(pageScroll)
        page.addSubview(content)
        NSLayoutConstraint.activate([
            pageScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageScroll.topAnchor.constraint(equalTo: view.topAnchor),
            pageScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            page.widthAnchor.constraint(equalTo: pageScroll.contentView.widthAnchor),
            content.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: page.topAnchor, constant: 28),
            content.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -28),
        ])
    }

    // MARK: - 自检

    func reload() {
        reload(nil)
    }

    @objc private func reload(_ sender: Any?) {
        let infoDict = Bundle.main.infoDictionary
        let version = infoDict?["CFBundleShortVersionString"] as? String ?? "dev"
        infoLabel.stringValue = "OpenBy v\(version)　macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        infoLabel.stringValue += "\n配置：\(redactHome(model.store.fileURL.path))"

        let build = infoDict?["CFBundleVersion"] as? String ?? "dev"
        infoLabel.stringValue += "\n构建：\(build) · PID \(ProcessInfo.processInfo.processIdentifier) · 后台常驻"
        infoLabel.stringValue += "\n应用：\(redactHome(Bundle.main.bundleURL.path))"
        if let date = infoDict?["OpenByBuildDate"] as? String { infoLabel.stringValue += " · " + date }
        infoLabel.toolTip = infoLabel.stringValue
        checkGeneration += 1
        let generation = checkGeneration
        let handlers = model.configuration.handlers
        let resolver = model.resolver
        let ownID = model.openByBundleID ?? ""
        resolver.invalidate()
        refreshButton.isEnabled = false
        DispatchQueue.global(qos: .utility).async {
            let service = AssociationService(provider: WorkspaceDefaultAppProvider())
            let rows = handlers.map { handler in
                let type = UTType(handler.contentTypeIdentifier)
                let takenOver = type.map { service.isManagedByOpenBy(contentType: $0, openByBundleID: ownID) } ?? false
                let appsOK = ([handler.fallbackApplication] + handler.rules.map(\.targetApplication)).allSatisfy {
                    resolver.applicationURL(for: $0) != nil
                }
                let foldersOK = handler.rules.allSatisfy { FileManager.default.fileExists(atPath: $0.folderPath) }
                let name = handler.displayExtensions.map { "." + $0 }.joined(separator: ", ")
                return Row(handlerName: name, takenOver: takenOver, appsOK: appsOK, foldersOK: foldersOK)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.checkGeneration == generation else { return }
                self.rows = rows
                self.tableView.reloadData()
                self.refreshButton.isEnabled = true
            }
        }
        model.diagnosticsProvider { [weak self] errors, measurements in
            guard let self, self.checkGeneration == generation else { return }
            self.errorsLabel.stringValue = errors.isEmpty ? "没有发现问题" : errors.joined(separator: "\n\n")
            self.errorsLabel.textColor = errors.isEmpty ? .secondaryLabelColor : .systemOrange
            var lines = [String(format: "本次进程入口 → 服务就绪：%.2f ms", self.model.startupMilliseconds)]
            let values = measurements.compactMap(\.dispatchMilliseconds).sorted()
            if !values.isEmpty {
                let p95 = values[min(values.count - 1, Int(ceil(Double(values.count) * 0.95)) - 1)]
                lines.append(String(format: "最近 %d 组收到事件 → 发出请求：P95 %.2f ms", values.count, p95))
            }
            lines.append("路由 / 排队 / 定位 / 发出请求（ms）；系统确认不等于窗口显示")
            for sample in measurements.suffix(5) {
                let sent = sample.dispatchMilliseconds.map { String(format: "%.2f", $0) } ?? "—"
                lines.append(String(format: "%@ ×%d  %.2f / %.2f / %.2f / %@  %@",
                                    sample.target, sample.fileCount, sample.routingMilliseconds,
                                    sample.queueMilliseconds, sample.resolutionMilliseconds, sent, sample.status))
            }
            if measurements.isEmpty { lines.append("暂无记录；打开文件后点击重新检查。") }
            self.performanceLabel.stringValue = lines.joined(separator: "\n")
        }
    }

    @objc private func exportConfig(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "OpenBy-config.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONEncoder.prettyPrinted.encode(model.configuration)
            try data.write(to: url, options: .atomic)
        } catch {
            NSSound.beep()
        }
    }

    private func redactHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        let entry = rows[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField
            ?? makeCell(identifier: identifier)
        switch identifier.rawValue {
        case "handler": cell.stringValue = entry.handlerName
        case "taken": cell.stringValue = entry.takenOver ? "已启用" : "尚未启用"
        case "apps": cell.stringValue = entry.appsOK ? "可用" : "⚠ 缺失"
        case "folders": cell.stringValue = entry.foldersOK ? "可用" : "⚠ 不存在"
        default: cell.stringValue = ""
        }
        return cell
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let cell = NSTextField(labelWithString: "")
        cell.identifier = identifier
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
