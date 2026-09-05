import AppKit
import UniformTypeIdentifiers

/// 规则列表：展示所选文件类型的文件夹规则，支持拖拽排序（first-match-wins），
/// 底部固定一条不可删除的回退应用行。规则编辑通过对话框完成。
@MainActor
final class RulesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let model: SettingsModel
    private let handlerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let headerLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let addButton = NSButton(title: "添加规则…", target: nil, action: nil)
    private let editButton = NSButton(title: "编辑…", target: nil, action: nil)
    private let deleteButton = NSButton(title: "删除规则", target: nil, action: nil)
    private let testButton = NSButton(title: "测试文件…", target: nil, action: nil)
    private let fallbackButton = NSButton(title: "更换默认应用…", target: nil, action: nil)
    private let resultLabel = NSTextField(labelWithString: "")
    private let tipLabel = NSTextField(labelWithString: "规则从上到下匹配，第一条命中即生效。拖拽行可调整顺序。")

    private var handlerID: UUID?
    private var editingID: UUID?

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

    // MARK: - 对外

    /// 聚焦到指定文件类型（来自文件类型列表双击）。
    func focus(handlerID: UUID) {
        if let index = model.configuration.handlers.firstIndex(where: { $0.id == handlerID }) {
            handlerPopup.selectItem(at: index)
        }
        self.handlerID = handlerID
        reload()
    }

    /// 刷新（配置变更后由设置窗口调用）。
    func reload() {
        rebuildPopup()
        tableView.reloadData()
        renderHeader()
        resultLabel.stringValue = ""
        resultLabel.textColor = .secondaryLabelColor
    }

    // MARK: - UI

    private func buildUI() {
        handlerPopup.target = self
        handlerPopup.action = #selector(handlerChanged(_:))

        headerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        headerLabel.lineBreakMode = .byTruncatingTail
        resultLabel.textColor = .secondaryLabelColor
        resultLabel.lineBreakMode = .byTruncatingTail
        tipLabel.textColor = .secondaryLabelColor
        tipLabel.font = .systemFont(ofSize: 11)
        tipLabel.lineBreakMode = .byTruncatingTail

        let columns: [(id: String, title: String, width: CGFloat)] = [
            ("folder", "文件夹", 280),
            ("recursive", "子文件夹", 70),
            ("target", "目标应用", 180),
            ("enabled", "启用", 60),
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
        tableView.doubleAction = #selector(editRow(_:))
        tableView.registerForDraggedTypes([.string])

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addButton.target = self
        addButton.action = #selector(addRule(_:))
        editButton.target = self
        editButton.action = #selector(editRow(_:))
        deleteButton.target = self
        deleteButton.action = #selector(deleteRule(_:))
        testButton.target = self
        testButton.action = #selector(testFile(_:))
        fallbackButton.target = self
        fallbackButton.action = #selector(changeFallback(_:))

        let row1 = NSStackView(views: [handlerPopup, headerLabel])
        row1.orientation = .horizontal
        row1.spacing = 10

        let row2 = NSStackView(views: [addButton, editButton, deleteButton])
        row2.orientation = .horizontal
        row2.spacing = 8

        let row3 = NSStackView(views: [testButton, fallbackButton])
        row3.orientation = .horizontal
        row3.spacing = 8

        for subview in [row1, scrollView, row2, row3, resultLabel, tipLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            row1.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            row1.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            row1.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            handlerPopup.widthAnchor.constraint(equalToConstant: 200),

            scrollView.topAnchor.constraint(equalTo: row1.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            row2.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10),
            row2.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            row3.topAnchor.constraint(equalTo: row2.bottomAnchor, constant: 8),
            row3.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            resultLabel.topAnchor.constraint(equalTo: row3.bottomAnchor, constant: 8),
            resultLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            resultLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            tipLabel.topAnchor.constraint(equalTo: resultLabel.bottomAnchor, constant: 4),
            tipLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tipLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tipLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    private func rebuildPopup() {
        let selectedID = handlerID
        handlerPopup.removeAllItems()
        handlerPopup.addItems(withTitles: model.configuration.handlers.map {
            $0.displayExtensions.joined(separator: ", ")
        })
        if let selectedID, let index = model.configuration.handlers.firstIndex(where: { $0.id == selectedID }) {
            handlerPopup.selectItem(at: index)
            handlerID = selectedID
        } else if model.configuration.handlers.count > 0 {
            handlerPopup.selectItem(at: 0)
            handlerID = model.configuration.handlers[0].id
        } else {
            handlerID = nil
        }
    }

    private func renderHeader() {
        guard let handler = currentHandler else {
            headerLabel.stringValue = "请先在「文件类型」中添加类型"
            return
        }
        let names = handler.displayExtensions.map { "." + $0 }.joined(separator: ", ")
        headerLabel.stringValue = "\(names)（\(handler.contentTypeIdentifier)）— 规则 \(handler.rules.count) 条"
    }

    private var currentHandler: FileHandler? {
        handlerID.flatMap { model.handler(id: $0) }
    }

    /// 规则行 + 固定回退行。回退行永远在最后。
    private var ruleCount: Int { currentHandler?.rules.count ?? 0 }
    private var fallbackRowIndex: Int { ruleCount }

    // MARK: - Actions

    @objc private func handlerChanged(_ sender: Any?) {
        let index = handlerPopup.indexOfSelectedItem
        if index >= 0, index < model.configuration.handlers.count {
            handlerID = model.configuration.handlers[index].id
        }
        reload()
    }

    @objc private func addRule(_ sender: Any?) {
        guard let handler = currentHandler else {
            NSSound.beep()
            return
        }
        presentRuleEditor(existing: nil, for: handler) { [weak self] edited in
            guard let self else { return }
            self.model.addRule(
                to: handler.id,
                folderPath: edited.folderPath,
                includesDescendants: edited.includesDescendants,
                target: edited.targetApplication
            )
            self.reload()
        }
    }

    @objc private func editRow(_ sender: Any?) {
        guard let handler = currentHandler else { return }
        let row = (sender as? NSTableView) === tableView ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < ruleCount else {
            // 双击回退行 → 更换默认应用。
            if row == fallbackRowIndex { changeFallback(sender) }
            return
        }
        let rule = handler.rules[row]
        presentRuleEditor(existing: rule, for: handler) { [weak self] edited in
            guard let self else { return }
            self.model.updateRule(handlerID: handler.id, ruleID: rule.id) { target in
                target.folderPath = PathInput.expandedAbsolutePath(edited.folderPath)
                target.includesDescendants = edited.includesDescendants
                target.enabled = edited.enabled
                target.targetApplication = edited.targetApplication
            }
            self.reload()
        }
    }

    @objc private func deleteRule(_ sender: Any?) {
        guard let handler = currentHandler else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < ruleCount else { NSSound.beep(); return }
        let rule = handler.rules[row]
        model.removeRule(handlerID: handler.id, ruleID: rule.id)
        reload()
    }

    @objc private func changeFallback(_ sender: Any?) {
        guard let handler = currentHandler else { return }
        guard let url = chooseApplication() else { return }
        let reference = SettingsModel.applicationReference(from: url)
        model.updateHandler(id: handler.id) { $0.fallbackApplication = reference }
        reload()
    }

    @objc private func testFile(_ sender: Any?) {
        guard currentHandler != nil else { NSSound.beep(); return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择任意文件，预览 OpenBy 将如何处理它（不会真正打开）"
        panel.beginSheetModal(for: view.window ?? NSWindow()) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let description = self.model.describeRouting(for: url)
            self.resultLabel.stringValue = "\(url.lastPathComponent) → \(description)"
            self.resultLabel.textColor = .labelColor
        }
    }

    private func presentRuleEditor(existing: FolderRule?, for handler: FileHandler, onSaved: @escaping (FolderRule) -> Void) {
        let isNew = existing == nil
        let rule = existing ?? FolderRule(folderPath: "~/", includesDescendants: true, targetApplication: handler.fallbackApplication)

        let folderField = NSTextField(string: rule.folderPath)
        folderField.placeholderString = "文件夹绝对路径（支持 ~ 前缀）"
        folderField.widthAnchor.constraint(equalToConstant: 320).isActive = true

        let descendantsButton = NSButton(checkboxWithTitle: "包含所有子文件（否则仅直接子文件）", target: nil, action: nil)
        descendantsButton.state = rule.includesDescendants ? .on : .off

        let enabledButton = NSButton(checkboxWithTitle: "启用这条规则", target: nil, action: nil)
        enabledButton.state = rule.enabled ? .on : .off

        var target = rule.targetApplication
        let targetLabel = NSTextField(labelWithString: "目标应用：\(target.displayName)（\(target.bundleIdentifier)）")
        targetLabel.lineBreakMode = .byTruncatingTail
        targetLabel.widthAnchor.constraint(equalToConstant: 320).isActive = true

        let chooseButton = NSButton(title: "选择应用…", target: nil, action: nil)

        let stack = NSStackView(views: [folderField, descendantsButton, enabledButton, targetLabel, chooseButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let alert = NSAlert()
        alert.messageText = isNew ? "添加规则" : "编辑规则"
        alert.informativeText = "命中此文件夹内的 \(handler.displayExtensions.joined(separator: ", ")) 文件将用目标应用打开。"
        alert.accessoryView = stack
        alert.addButton(withTitle: isNew ? "添加" : "保存")
        alert.addButton(withTitle: "取消")

        // 用关联对象在按钮上携带回调，避免 target 强引用循环。
        ChooseAppTarget.attach(to: chooseButton) { [weak targetLabel] url in
            guard let url else { return }
            let ref = SettingsModel.applicationReference(from: url)
            target = ref
            targetLabel?.stringValue = "目标应用：\(ref.displayName)（\(ref.bundleIdentifier)）"
        }

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            var result = rule
            result.folderPath = PathInput.expandedAbsolutePath(folderField.stringValue)
            result.includesDescendants = descendantsButton.state == .on
            result.enabled = enabledButton.state == .on
            result.targetApplication = target
            onSaved(result)
        }
    }

    private func chooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.message = "选择要用来打开该类型文件的应用"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        ruleCount + 1
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField
            ?? makeCell(identifier: identifier)

        guard row >= 0 else { return cell }
        if row == fallbackRowIndex {
            switch identifier.rawValue {
            case "folder": cell.stringValue = "（未命中任何规则时）"
            case "recursive": cell.stringValue = "—"
            case "target": cell.stringValue = currentHandler?.fallbackApplication.displayName ?? "—"
            case "enabled": cell.stringValue = "回退"
            default: cell.stringValue = ""
            }
            cell.textColor = .secondaryLabelColor
            return cell
        }

        cell.textColor = .labelColor
        guard let rule = currentHandler?.rules[row] else { return cell }
        switch identifier.rawValue {
        case "folder": cell.stringValue = redactHome(rule.folderPath)
        case "recursive": cell.stringValue = rule.includesDescendants ? "全部" : "仅直接"
        case "target": cell.stringValue = rule.targetApplication.displayName
        case "enabled": cell.stringValue = rule.enabled ? "✓" : "✗"
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

    private func redactHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - 拖拽排序（回退行不可拖动，也不接受落到自身）

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < ruleCount else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: .string)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard dropOperation == .above else { return [] }
        let targetRow = min(row, ruleCount)
        tableView.setDropRow(targetRow, dropOperation: .above)
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let handler = currentHandler,
              let string = info.draggingPasteboard.string(forType: .string),
              let sourceRow = Int(string),
              sourceRow < ruleCount else { return false }
        model.moveRule(handlerID: handler.id, from: sourceRow, to: min(row, ruleCount))
        reload()
        return true
    }
}

/// 在“选择应用”按钮上附带回调的桥接对象。
private final class ChooseAppTarget: NSObject {
    private var handler: ((URL?) -> Void)?

    private static var key: UInt8 = 0

    static func attach(to button: NSButton, handler: @escaping (URL?) -> Void) {
        let target = ChooseAppTarget()
        target.handler = handler
        button.target = target
        button.action = #selector(ChooseAppTarget.chosen(_:))
        objc_setAssociatedObject(button, &key, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    @objc private func chosen(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.message = "选择应用"
        guard panel.runModal() == .OK else { return }
        handler?(panel.url)
    }
}
