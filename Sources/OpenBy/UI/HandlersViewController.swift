import AppKit
import UniformTypeIdentifiers

/// 文件类型列表：添加扩展名 / 拖入示例文件、设为默认 / 停止接管 / 删除、状态展示。
@MainActor
final class HandlersViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let model: SettingsModel
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let extensionField = NSTextField(string: "")
    private let addButton = SettingsButton(title: "添加扩展名", target: nil, action: nil)
    private let takeOverButton = SettingsButton(title: "设为默认", target: nil, action: nil)
    private let stopButton = SettingsButton(title: "停止接管", target: nil, action: nil)
    private let deleteButton = SettingsButton(title: "删除", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    private var selectedHandler: FileHandler? {
        let row = tableView.selectedRow
        guard row >= 0, row < model.configuration.handlers.count else { return nil }
        return model.configuration.handlers[row]
    }

    init(model: SettingsModel) {
        self.model = model
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

    func reload() {
        tableView.reloadData()
        refreshStatus()
    }

    // MARK: - UI

    private func buildUI() {
        let columns: [(id: String, title: String, width: CGFloat)] = [
            ("ext", "扩展名", 90),
            ("uti", "UTI", 160),
            ("current", "当前默认", 180),
            ("managed", "已接管", 70),
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
        tableView.allowsMultipleSelection = false
        // 拖入示例文件以添加扩展名。
        tableView.registerForDraggedTypes([.fileURL])

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        extensionField.placeholderString = "如 pdf"
        extensionField.translatesAutoresizingMaskIntoConstraints = false
        extensionField.target = self
        extensionField.action = #selector(addExtension(_:))
        addButton.target = self
        addButton.action = #selector(addExtension(_:))
        takeOverButton.target = self
        takeOverButton.action = #selector(takeOver(_:))
        stopButton.target = self
        stopButton.action = #selector(stopTakeOver(_:))
        deleteButton.target = self
        deleteButton.action = #selector(deleteHandler(_:))

        let hint = NSTextField(labelWithString: "提示：可把示例文件拖到列表中添加扩展名")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingTail

        let buttons = NSStackView(views: [addButton, takeOverButton, stopButton, deleteButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        for subview in [scrollView, extensionField, buttons, hint, statusLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            extensionField.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            extensionField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            extensionField.widthAnchor.constraint(equalToConstant: 120),

            buttons.leadingAnchor.constraint(equalTo: extensionField.trailingAnchor, constant: 8),
            buttons.centerYAnchor.constraint(equalTo: extensionField.centerYAnchor),

            hint.topAnchor.constraint(equalTo: extensionField.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            statusLabel.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])

        tableView.action = #selector(selectionChanged(_:))
    }

    private func refreshStatus() {
        let count = model.configuration.handlers.count
        statusLabel.stringValue = count == 0 ? "尚未添加文件类型" : "共 \(count) 个文件类型"
    }

    // MARK: - Actions

    @objc private func addExtension(_ sender: Any?) {
        guard let handler = model.addHandler(extension: extensionField.stringValue) else {
            NSSound.beep()
            return
        }
        extensionField.stringValue = ""
        tableView.reloadData()
        if let index = model.configuration.handlers.firstIndex(where: { $0.id == handler.id }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        refreshStatus()
    }

    @objc private func takeOver(_ sender: Any?) {
        guard let handler = selectedHandler,
              let type = UTType(handler.contentTypeIdentifier) else { return }
        model.takeOver(handlerID: handler.id, contentType: type) { [weak self] result in
            Task { @MainActor in self?.handleTakeOverResult(result, handler: handler) }
        }
    }

    private func handleTakeOverResult(_ result: Result<Bool, Error>, handler: FileHandler) {
        switch result {
        case .success(true):
            showMessage("已接管 \(handler.displayExtensions.first ?? handler.contentTypeIdentifier)：OpenBy 现在是默认处理器。")
        case .success(false):
            showMessage("尚未接管：系统确认可能被拒绝，或默认关联尚未生效。请重试。")
        case .failure(let error):
            showMessage("接管失败：\(error.localizedDescription)")
        }
        tableView.reloadData()
    }

    @objc private func stopTakeOver(_ sender: Any?) {
        guard let handler = selectedHandler,
              let type = UTType(handler.contentTypeIdentifier) else { return }
        model.restoreDefault(handlerID: handler.id, contentType: type) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(true): self.showMessage("已恢复接管前默认应用。")
                case .success(false): self.showMessage("未执行恢复：当前默认已不是 OpenBy（尊重你的手动选择），或没有可恢复的默认应用。")
                case .failure(let error): self.showMessage("恢复失败：\(error.localizedDescription)")
                }
                self.tableView.reloadData()
            }
        }
    }

    @objc private func deleteHandler(_ sender: Any?) {
        guard let handler = selectedHandler else { return }
        model.removeHandler(id: handler.id)
        tableView.reloadData()
        refreshStatus()
    }

    private func showMessage(_ text: String) {
        statusLabel.stringValue = text
        statusLabel.textColor = .labelColor
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        model.configuration.handlers.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < model.configuration.handlers.count else { return nil }
        let handler = model.configuration.handlers[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField
            ?? makeCell(identifier: identifier)

        switch identifier.rawValue {
        case "ext":
            cell.stringValue = handler.displayExtensions.joined(separator: ", ")
        case "uti":
            cell.stringValue = handler.contentTypeIdentifier
        case "current":
            let type = UTType(handler.contentTypeIdentifier)
            let bundleID = type.flatMap { model.associationService.currentDefaultApplicationBundleID(for: $0) } ?? "—"
            cell.stringValue = displayName(forBundleID: bundleID)
        case "managed":
            let type = UTType(handler.contentTypeIdentifier)
            let managed = type.map { model.isManaged(handler: handler, contentType: $0) } ?? false
            cell.stringValue = managed ? "✓" : ""
        default:
            cell.stringValue = ""
        }
        return cell
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let cell = NSTextField(labelWithString: "")
        cell.identifier = identifier
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }

    private func displayName(forBundleID bundleID: String) -> String {
        guard !bundleID.isEmpty else { return "—" }
        let reference = ApplicationReference(bundleIdentifier: bundleID, displayName: bundleID)
        guard let url = model.resolver.applicationURL(for: reference) else { return bundleID }
        return url.deletingPathExtension().lastPathComponent
    }

    @objc private func selectionChanged(_ sender: Any?) {
        // 双击行：进入规则编辑（由窗口控制器切换 tab）。
        if tableView.clickedRow >= 0 {
            onSelectHandler?(model.configuration.handlers[tableView.clickedRow])
        }
    }

    var onSelectHandler: ((FileHandler) -> Void)?

    // MARK: - 拖入示例文件

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let url = NSURL(from: info.draggingPasteboard) as URL? else { return false }
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        let result = model.addHandler(extension: ext)
        if result != nil {
            tableView.reloadData()
            refreshStatus()
            return true
        }
        return false
    }
}
