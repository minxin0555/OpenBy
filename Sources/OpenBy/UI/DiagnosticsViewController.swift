import AppKit
import UniformTypeIdentifiers

/// 诊断：应用/配置路径、导出配置、逐文件类型自检（默认关联、目标应用、规则文件夹）、最近错误。
@MainActor
final class DiagnosticsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let model: SettingsModel
    private let recentErrorsProvider: () -> [String]

    private let infoLabel = NSTextField(labelWithString: "")
    private let exportButton = NSButton(title: "导出配置…", target: nil, action: nil)
    private let refreshButton = NSButton(title: "重新自检", target: nil, action: nil)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let errorsTitle = NSTextField(labelWithString: "最近错误（仅内存，不落盘）")
    private let errorsLabel = NSTextField(labelWithString: "暂无")

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
        infoLabel.lineBreakMode = .byTruncatingTail
        errorsTitle.font = .systemFont(ofSize: 12, weight: .medium)
        errorsLabel.textColor = .secondaryLabelColor
        errorsLabel.font = .systemFont(ofSize: 11)
        errorsLabel.lineBreakMode = .byTruncatingMiddle
        errorsLabel.maximumNumberOfLines = 6

        exportButton.target = self
        exportButton.action = #selector(exportConfig(_:))
        refreshButton.target = self
        refreshButton.action = #selector(reload(_:))

        let columns: [(id: String, title: String, width: CGFloat)] = [
            ("handler", "文件类型", 120),
            ("taken", "默认=OpenBy", 100),
            ("apps", "目标应用存在", 110),
            ("folders", "规则文件夹存在", 110),
        ]
        for col in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.id))
            column.title = col.title
            column.width = col.width
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .none

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let buttons = NSStackView(views: [exportButton, refreshButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        for subview in [infoLabel, buttons, scrollView, errorsTitle, errorsLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            infoLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            infoLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -12),

            buttons.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.heightAnchor.constraint(equalToConstant: 200),

            errorsTitle.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            errorsTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            errorsLabel.topAnchor.constraint(equalTo: errorsTitle.bottomAnchor, constant: 4),
            errorsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            errorsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            errorsLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
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

        rows = model.configuration.handlers.map { handler in
            let type = UTType(handler.contentTypeIdentifier)
            let takenOver = type.map { model.isManaged(handler: handler, contentType: $0) } ?? false
            var allAppsOK = true
            if model.resolver.applicationURL(for: handler.fallbackApplication) == nil { allAppsOK = false }
            for rule in handler.rules {
                if model.resolver.applicationURL(for: rule.targetApplication) == nil { allAppsOK = false }
            }
            let foldersOK = handler.rules.allSatisfy { FileManager.default.fileExists(atPath: $0.folderPath) }
            let name = handler.displayExtensions.map { "." + $0 }.joined(separator: ", ")
            return Row(handlerName: name, takenOver: takenOver, appsOK: allAppsOK, foldersOK: foldersOK)
        }
        tableView.reloadData()

        let errors = recentErrorsProvider()
        if errors.isEmpty {
            errorsLabel.stringValue = "暂无"
            errorsLabel.textColor = .secondaryLabelColor
        } else {
            errorsLabel.stringValue = errors.suffix(6).joined(separator: "\n")
            errorsLabel.textColor = .systemOrange
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
        case "taken": cell.stringValue = entry.takenOver ? "✓" : "—"
        case "apps": cell.stringValue = entry.appsOK ? "✓" : "✗ 缺失"
        case "folders": cell.stringValue = entry.foldersOK ? "✓" : "✗ 不存在"
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
