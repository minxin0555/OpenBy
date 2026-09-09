import AppKit
import UniformTypeIdentifiers

/// Shared native presentation primitives. Colors follow the window's effective appearance.
@MainActor
enum SettingsStyle {
    static func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    static func row(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    static func column(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.distribution = .fill
        stack.alignment = .leading
        stack.spacing = spacing
        for view in views {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    static func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return view
    }

    static func size(_ view: NSView, _ size: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    static func button(_ button: NSButton, symbol: String? = nil) {
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12)
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
        }
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    static func group(_ content: NSView, inset: CGFloat = 16) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.borderWidth = 1
        box.cornerRadius = 10
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.masksToBounds = true
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        box.contentViewMargins = .zero
        let container = NSView()
        box.contentView = container
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
        ])
        return box
    }
}

@MainActor
final class SettingsFlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class SettingsTypeCell: NSTableCellView {
    let name = SettingsStyle.label("", weight: .medium)
    let subtitle = SettingsStyle.label("", size: 11, color: .secondaryLabelColor)
    let icon = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        SettingsStyle.size(icon, 28)
        name.lineBreakMode = .byTruncatingTail
        subtitle.lineBreakMode = .byTruncatingTail
        textField = name
        imageView = icon
        let row = SettingsStyle.row([icon, SettingsStyle.column([name, subtitle], spacing: 4)], spacing: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }
}

@MainActor
private final class SettingsRuleCell: NSTableCellView {
    let order = SettingsStyle.label("", size: 11, color: .secondaryLabelColor)
    let folder = SettingsStyle.label("", weight: .medium)
    let path = SettingsStyle.label("", size: 11, color: .secondaryLabelColor)
    let scope = SettingsStyle.label("", size: 11, color: .secondaryLabelColor)
    let appName = SettingsStyle.label("", size: 12, weight: .medium)
    let appIcon = NSImageView()
    let edit = NSButton(title: "编辑", target: nil, action: nil)
    let more = NSPopUpButton(frame: .zero, pullsDown: true)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let folderIcon = NSImageView(image: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage())
        folderIcon.contentTintColor = .systemBlue
        SettingsStyle.size(folderIcon, 18)
        SettingsStyle.size(appIcon, 24)
        folder.lineBreakMode = .byTruncatingTail
        path.lineBreakMode = .byTruncatingMiddle
        scope.lineBreakMode = .byTruncatingTail
        appName.lineBreakMode = .byTruncatingTail
        order.widthAnchor.constraint(equalToConstant: 16).isActive = true
        order.alignment = .center
        order.toolTip = "拖动规则调整优先级，也可在更多菜单中上移或下移"
        let location = SettingsStyle.column([SettingsStyle.row([folderIcon, folder], spacing: 6), path, scope], spacing: 3)
        location.setContentHuggingPriority(.init(1), for: .horizontal)
        location.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let application = SettingsStyle.row([appIcon, appName], spacing: 8)
        application.widthAnchor.constraint(equalToConstant: 140).isActive = true
        SettingsStyle.button(edit)
        edit.isBordered = false
        more.bezelStyle = .rounded
        more.isBordered = false
        more.imagePosition = .imageOnly
        more.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let arrow = SettingsStyle.label("→", color: .secondaryLabelColor)
        arrow.widthAnchor.constraint(equalToConstant: 14).isActive = true
        let row = SettingsStyle.row([order, location, arrow, application, edit, more], spacing: 8)
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }
}

/// OpenBy 的主设置窗口。
///
/// 界面按用户任务组织为「文件类型列表 + 当前类型的完整打开方式」，不再要求用户在
/// “文件类型 / 规则 / 诊断”三个技术页签之间来回切换。
@MainActor
final class SettingsWindowController: NSWindowController {
    private let contentController: SettingsWorkspaceViewController
    private var didBuildContent = false

    init(model: SettingsModel) {
        contentController = SettingsWorkspaceViewController(model: model)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenBy"
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 800, height: 560)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    func show() {
        if !didBuildContent {
            window?.contentViewController = contentController
            window?.setContentSize(NSSize(width: 960, height: 680))
            window?.center()
            didBuildContent = true
        }
        contentController.reload()
        showWindow(nil)
    }

    func reloadFromModel() {
        contentController.reload()
    }
}

/// 单窗口主从界面：左侧选择文件类型，右侧完成启用、规则和其他位置。
@MainActor
private final class SettingsWorkspaceViewController: NSViewController,
    NSTableViewDataSource,
    NSTableViewDelegate
{
    private let model: SettingsModel

    private let sidebar = NSVisualEffectView()
    private let sidebarTitle = NSTextField(labelWithString: "文件类型与格式组")
    private let handlerTable = NSTableView()
    private let handlerScroll = NSScrollView()
    private let addTypeButton = NSButton(title: "添加文件类型…", target: nil, action: nil)

    private let detailContainer = DropTargetView()
    private let emptyView = NSView()
    private let detailView = SettingsFlippedView()
    private let detailScroll = NSScrollView()
    private let typeIcon = NSImageView()
    private let typeSubtitle = NSTextField(labelWithString: "")
    private let fallbackIcon = NSImageView()
    private let moreButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private var ruleHeight: NSLayoutConstraint!
    private var editorSession: RuleEditorSession?
    private var associationBusy = false
    private let iconCache = NSCache<NSString, NSImage>()
    private static let ruleDragType = NSPasteboard.PasteboardType("app.openby.rule-row")
    private let emptyFeedback = NSTextField(wrappingLabelWithString: "")

    private let typeTitle = NSTextField(labelWithString: "")
    private let statusDot = NSTextField(labelWithString: "●")
    private let statusLabel = NSTextField(labelWithString: "")
    private let enableButton = NSButton(title: "", target: nil, action: nil)

    private let rulesTitle = NSTextField(labelWithString: "按文件所在位置选择应用")
    private let rulesExplanation = NSTextField(labelWithString: "如果一个文件同时符合多条规则，将优先使用排在上面的规则。")
    private let ruleTable = NSTableView()
    private let ruleScroll = NSScrollView()
    private let rulesEmptyLabel = NSTextField(labelWithString: "还没有位置规则。添加一条规则，让特定文件夹里的文件使用指定应用打开。")
    private let addRuleButton = NSButton(title: "添加位置规则…", target: nil, action: nil)

    private let fallbackTitle = NSTextField(labelWithString: "其他位置")
    private let fallbackDescription = NSTextField(labelWithString: "没有匹配到上方规则时，使用：")
    private let fallbackApplication = NSTextField(labelWithString: "")
    private let changeFallbackButton = NSButton(title: "更改…", target: nil, action: nil)

    private let feedbackLabel = NSTextField(wrappingLabelWithString: "")

    private var selectedHandlerID: UUID?

    private var currentHandler: FileHandler? {
        selectedHandlerID.flatMap { model.handler(id: $0) }
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

    func reload(message: String? = nil, isError: Bool = false) {
        let handlers = model.configuration.handlers
        if let selectedHandlerID,
           !handlers.contains(where: { $0.id == selectedHandlerID }) {
            self.selectedHandlerID = nil
        }
        if self.selectedHandlerID == nil {
            self.selectedHandlerID = handlers.first?.id
        }

        handlerTable.reloadData()
        if let id = selectedHandlerID,
           let index = handlers.firstIndex(where: { $0.id == id }) {
            handlerTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }

        renderDetail(message: message, isError: isError)
    }

    // MARK: - 构建界面

    private func buildUI() {
        buildSidebar()
        buildEmptyState()
        buildDetail()

        let divider = NSBox()
        divider.boxType = .separator

        for child in [sidebar, divider, detailContainer] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }

        detailContainer.onFileDrop = { [weak self] url in
            self?.addFileType(from: url)
        }

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 224),

            divider.topAnchor.constraint(equalTo: view.topAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            detailContainer.topAnchor.constraint(equalTo: view.topAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            detailContainer.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func buildSidebar() {
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .followsWindowActiveState
        sidebarTitle.stringValue = "文件类型"
        sidebarTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        sidebarTitle.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("handler"))
        handlerTable.addTableColumn(column)
        handlerTable.headerView = nil
        handlerTable.style = .sourceList
        handlerTable.rowHeight = 56
        handlerTable.intercellSpacing = NSSize(width: 0, height: 4)
        handlerTable.backgroundColor = .clear
        handlerTable.dataSource = self
        handlerTable.delegate = self
        handlerTable.allowsMultipleSelection = false
        handlerTable.setAccessibilityLabel("管理的文件类型")
        handlerTable.registerForDraggedTypes([.fileURL])
        handlerScroll.documentView = handlerTable
        handlerScroll.hasVerticalScroller = true
        handlerScroll.autohidesScrollers = true
        handlerScroll.drawsBackground = false

        SettingsStyle.button(addTypeButton, symbol: "plus")
        addTypeButton.target = self
        addTypeButton.action = #selector(showAddFileType(_:))
        let footer = SettingsStyle.column([addTypeButton], spacing: 8)
        for child in [sidebarTitle, handlerScroll, footer] {
            child.translatesAutoresizingMaskIntoConstraints = false
            sidebar.addSubview(child)
        }
        NSLayoutConstraint.activate([
            sidebarTitle.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 22),
            sidebarTitle.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20),
            handlerScroll.topAnchor.constraint(equalTo: sidebarTitle.bottomAnchor, constant: 12),
            handlerScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            handlerScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),
            handlerScroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            footer.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -16),
        ])
    }

    private func buildEmptyState() {
        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 42, weight: .regular)
        icon.contentTintColor = .controlAccentColor

        let title = NSTextField(labelWithString: "让文件找到合适的应用")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.alignment = .center

        let explanation = NSTextField(wrappingLabelWithString: "选择预设、输入后缀或选择示例文件来创建格式组，为组内格式统一设置打开应用。")
        explanation.textColor = .secondaryLabelColor
        explanation.alignment = .center
        explanation.maximumNumberOfLines = 3

        let steps = NSTextField(wrappingLabelWithString: "添加类型  →  设置规则  →  启用自动打开")
        steps.font = .systemFont(ofSize: 13, weight: .medium)
        steps.textColor = .secondaryLabelColor
        steps.maximumNumberOfLines = 3

        let chooseButton = NSButton(title: "添加文件类型…", target: self, action: #selector(showAddFileType(_:)))
        chooseButton.bezelStyle = .rounded
        chooseButton.keyEquivalent = "\r"

        let dragHint = NSTextField(labelWithString: "也可以把任意文件拖到这个窗口")
        dragHint.font = .systemFont(ofSize: 11)
        dragHint.textColor = .tertiaryLabelColor

        emptyFeedback.font = .systemFont(ofSize: 12)
        emptyFeedback.alignment = .center
        emptyFeedback.isHidden = true

        let stack = NSStackView(views: [icon, title, explanation, steps, chooseButton, dragHint, emptyFeedback])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(16, after: explanation)
        stack.setCustomSpacing(18, after: steps)
        stack.translatesAutoresizingMaskIntoConstraints = false

        emptyView.addSubview(stack)
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(emptyView)

        NSLayoutConstraint.activate([
            emptyView.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            emptyView.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
            emptyView.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor, constant: -20),
            explanation.widthAnchor.constraint(lessThanOrEqualToConstant: 430),
            stack.widthAnchor.constraint(lessThanOrEqualTo: emptyView.widthAnchor, constant: -56),
            emptyFeedback.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
        ])
    }

    private func buildDetail() {
        detailScroll.drawsBackground = false
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.documentView = detailView
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        detailView.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(detailScroll)
        NSLayoutConstraint.activate([
            detailScroll.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            detailScroll.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
            detailScroll.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailScroll.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailView.widthAnchor.constraint(equalTo: detailScroll.contentView.widthAnchor),
        ])

        typeTitle.font = .systemFont(ofSize: 24, weight: .semibold)
        typeTitle.lineBreakMode = .byTruncatingTail
        typeSubtitle.font = .systemFont(ofSize: 12)
        typeSubtitle.textColor = .secondaryLabelColor
        typeSubtitle.lineBreakMode = .byTruncatingTail
        SettingsStyle.size(typeIcon, 44)
        SettingsStyle.size(fallbackIcon, 32)
        let heading = SettingsStyle.row([typeIcon, SettingsStyle.column([typeTitle, typeSubtitle], spacing: 4)], spacing: 12)
        statusDot.font = .systemFont(ofSize: 10)
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.lineBreakMode = .byTruncatingTail
        let status = SettingsStyle.row([statusDot, statusLabel, SettingsStyle.spacer()], spacing: 5)
        SettingsStyle.button(enableButton)
        enableButton.target = self
        enableButton.action = #selector(toggleManaged(_:))
        moreButton.bezelStyle = .rounded
        moreButton.imagePosition = .imageOnly
        moreButton.setAccessibilityLabel("文件类型更多操作")
        let header = SettingsStyle.row([heading, SettingsStyle.spacer(), enableButton, moreButton], spacing: 12)

        rulesTitle.stringValue = "位置规则"
        rulesTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        rulesExplanation.stringValue = "从上到下匹配，首条符合的规则生效。拖动可调整顺序。"
        rulesExplanation.font = .systemFont(ofSize: 11)
        rulesExplanation.textColor = .secondaryLabelColor
        rulesExplanation.lineBreakMode = .byTruncatingTail
        rulesEmptyLabel.stringValue = "还没有位置规则\n所有文件将使用下方应用打开。"
        rulesEmptyLabel.font = .systemFont(ofSize: 12)
        rulesEmptyLabel.textColor = .secondaryLabelColor
        rulesEmptyLabel.alignment = .center
        rulesEmptyLabel.maximumNumberOfLines = 2
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("route"))
        column.resizingMask = .autoresizingMask
        ruleTable.addTableColumn(column)
        ruleTable.headerView = nil
        ruleTable.style = .plain
        ruleTable.rowHeight = 78
        ruleTable.intercellSpacing = .zero
        ruleTable.backgroundColor = .controlBackgroundColor
        ruleTable.dataSource = self
        ruleTable.delegate = self
        ruleTable.target = self
        ruleTable.doubleAction = #selector(editRule(_:))
        ruleTable.allowsMultipleSelection = false
        ruleTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        ruleTable.setAccessibilityLabel("位置规则，按优先级排序")
        ruleTable.registerForDraggedTypes([Self.ruleDragType])
        ruleTable.setDraggingSourceOperationMask(.move, forLocal: true)
        ruleScroll.documentView = ruleTable
        ruleScroll.hasVerticalScroller = true
        ruleScroll.autohidesScrollers = true
        ruleScroll.borderType = .noBorder
        ruleHeight = ruleScroll.heightAnchor.constraint(equalToConstant: 156)
        ruleHeight.isActive = true
        let ruleGroup = SettingsStyle.group(ruleScroll, inset: 0)
        rulesEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        ruleGroup.addSubview(rulesEmptyLabel)
        NSLayoutConstraint.activate([
            rulesEmptyLabel.centerXAnchor.constraint(equalTo: ruleGroup.centerXAnchor),
            rulesEmptyLabel.centerYAnchor.constraint(equalTo: ruleGroup.centerYAnchor),
            rulesEmptyLabel.widthAnchor.constraint(lessThanOrEqualTo: ruleGroup.widthAnchor, constant: -32),
        ])
        addRuleButton.title = "添加规则"
        SettingsStyle.button(addRuleButton, symbol: "plus")
        addRuleButton.target = self
        addRuleButton.action = #selector(addRule(_:))
        let rulesHeader = SettingsStyle.row([rulesTitle, SettingsStyle.spacer(), addRuleButton])
        let rules = SettingsStyle.column([rulesHeader, rulesExplanation, ruleGroup], spacing: 10)

        fallbackTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        fallbackApplication.font = .systemFont(ofSize: 13, weight: .medium)
        fallbackApplication.lineBreakMode = .byTruncatingTail
        fallbackDescription.stringValue = "没有规则匹配时，使用此应用"
        fallbackDescription.font = .systemFont(ofSize: 11)
        fallbackDescription.textColor = .secondaryLabelColor
        SettingsStyle.button(changeFallbackButton)
        changeFallbackButton.target = self
        changeFallbackButton.action = #selector(changeFallback(_:))
        let fallbackText = SettingsStyle.column([fallbackApplication, fallbackDescription], spacing: 4)
        let fallbackRow = SettingsStyle.row([fallbackIcon, fallbackText, SettingsStyle.spacer(), changeFallbackButton], spacing: 12)
        let fallback = SettingsStyle.column([fallbackTitle, SettingsStyle.group(fallbackRow)], spacing: 10)

        feedbackLabel.font = .systemFont(ofSize: 12)
        feedbackLabel.maximumNumberOfLines = 0
        feedbackLabel.isSelectable = true
        feedbackLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        let content = SettingsStyle.column([header, status, rules, fallback, feedbackLabel], spacing: 24)
        content.setCustomSpacing(8, after: header)
        content.translatesAutoresizingMaskIntoConstraints = false
        detailView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: detailView.topAnchor, constant: 28),
            content.leadingAnchor.constraint(equalTo: detailView.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: detailView.trailingAnchor, constant: -28),
            content.bottomAnchor.constraint(equalTo: detailView.bottomAnchor, constant: -28),
        ])
    }

    // MARK: - 渲染状态

    private func renderDetail(message: String?, isError: Bool) {
        let hasHandler = currentHandler != nil
        emptyView.isHidden = hasHandler
        detailScroll.isHidden = !hasHandler
        emptyFeedback.stringValue = message ?? ""
        emptyFeedback.textColor = isError ? .systemRed : .secondaryLabelColor
        emptyFeedback.isHidden = message == nil
        guard let handler = currentHandler else { return }

        let names = handler.displayExtensions.map { "." + $0.uppercased() }.joined(separator: "、")
        typeTitle.stringValue = typeDisplayName(handler)
        typeSubtitle.stringValue = names.lowercased()
        typeSubtitle.toolTip = typeSubtitle.stringValue
        typeIcon.image = UTType(handler.contentTypeIdentifier).map { NSWorkspace.shared.icon(for: $0) }

        let health = healthState(for: handler)
        statusDot.textColor = health.color
        statusLabel.textColor = health.color
        statusLabel.stringValue = health.text

        let managed = isManaged(handler)
        enableButton.title = associationBusy ? "正在更新…" : (model.managedCount(handler) > 0 && !managed ? "启用剩余格式" : "启用自动打开")
        enableButton.isHidden = managed && !associationBusy
        enableButton.isEnabled = !associationBusy
        enableButton.bezelColor = .controlAccentColor
        addRuleButton.bezelColor = managed ? .controlAccentColor : nil
        moreButton.isEnabled = !associationBusy
        handlerTable.isEnabled = !associationBusy
        addTypeButton.isEnabled = !associationBusy
        rebuildTypeMenu(managed: model.managedCount(handler) > 0)
        enableButton.toolTip = managed
            ? "让 macOS 恢复使用 OpenBy 启用前的默认应用"
            : "让 OpenBy 成为这种文件的默认打开应用"

        fallbackApplication.stringValue = handler.fallbackApplication.bundleIdentifier.isEmpty
            ? "尚未设置"
            : handler.fallbackApplication.displayName

        fallbackIcon.image = applicationIcon(handler.fallbackApplication)
        fallbackApplication.toolTip = fallbackApplication.stringValue
        ruleHeight.constant = CGFloat(max(1, min(5, handler.rules.count))) * 78
        ruleTable.reloadData()
        rulesEmptyLabel.isHidden = !handler.rules.isEmpty

        if associationBusy {
            statusLabel.stringValue = "正在更新自动打开状态，请稍候…"
            statusLabel.textColor = .secondaryLabelColor
            statusDot.textColor = .secondaryLabelColor
        }
        if let message {
            feedbackLabel.stringValue = message
            feedbackLabel.textColor = isError ? .systemRed : .labelColor
        } else if handler.rules.isEmpty {
            feedbackLabel.stringValue = "下一步：添加位置规则，或直接启用并让所有其他位置使用 \(fallbackApplication.stringValue) 打开。"
            feedbackLabel.textColor = .secondaryLabelColor
        } else {
            feedbackLabel.stringValue = ""
            feedbackLabel.textColor = .secondaryLabelColor
        }
        feedbackLabel.isHidden = feedbackLabel.stringValue.isEmpty
    }

    private func isManaged(_ handler: FileHandler) -> Bool {
        guard let type = UTType(handler.contentTypeIdentifier) else { return false }
        return model.isManaged(handler: handler, contentType: type)
    }

    private func healthState(for handler: FileHandler) -> (text: String, color: NSColor) {
        let count = model.managedCount(handler)
        if count > 0 && count < handler.contentTypes.count {
            return ("部分启用 · \(count)/\(handler.contentTypes.count) 种格式", .systemOrange)
        }
        let missingFolder = handler.rules.contains {
            $0.enabled && !FileManager.default.fileExists(atPath: PathInput.expandedAbsolutePath($0.folderPath))
        }
        let apps = [handler.fallbackApplication] + handler.rules.filter(\.enabled).map(\.targetApplication)
        let missingApp = apps.contains {
            $0.bundleIdentifier.isEmpty || model.resolver.applicationURL(for: $0) == nil
        }
        if missingFolder || missingApp {
            return ((isManaged(handler) ? "已启用 · " : "尚未启用 · ") + "有文件夹或应用不可用", .systemOrange)
        }
        if isManaged(handler) {
            return ("已启用自动打开", .systemGreen)
        }
        if handler.rules.isEmpty {
            return ("尚未启用 · 可以先添加位置规则", .systemOrange)
        }
        return ("尚未启用", .secondaryLabelColor)
    }

    // MARK: - 文件类型

    @objc private func showAddFileType(_ sender: Any?) {
        presentFormatGroupEditor(existing: nil)
    }

    @objc private func editFormatGroup(_ sender: Any?) {
        guard let handler = currentHandler else { return }
        presentFormatGroupEditor(existing: handler)
    }

    private func presentFormatGroupEditor(existing: FileHandler?) {
        guard !associationBusy else { return }
        let draft = FormatGroupDraft(existing: existing)
        let alert = NSAlert()
        alert.messageText = existing == nil ? "添加文件类型或格式组" : "编辑格式组"
        alert.informativeText = "选择预设后可以删改下方后缀，例如删除 png 或加入 avif。组内格式共用打开应用和位置规则。"
        alert.addButton(withTitle: existing == nil ? "添加" : "保存")
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "添加示例文件…")
        alert.accessoryView = draft.view
        alert.window.initialFirstResponder = draft.extensionsField

        while true {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                guard let extensions = FormatGroups.parseExtensions(draft.extensionsField.stringValue) else {
                    alert.informativeText = "请填写至少一个有效后缀，用逗号或空格分隔，例如 jpg, png。不要输入文件名或路径。"
                    continue
                }
                let invalid = extensions.filter { UTType(filenameExtension: $0) == nil }
                guard invalid.isEmpty else {
                    alert.informativeText = "无法识别这些后缀：\(invalid.joined(separator: ", "))。请修改后再保存。"
                    continue
                }
                if let conflict = model.conflictingHandler(extensions: extensions, excluding: existing?.id) {
                    alert.informativeText = "部分格式已属于“\(typeDisplayName(conflict))”。请从当前列表去除重复格式，或先编辑已有组；原有规则不会被覆盖。"
                    continue
                }
                let inputName = draft.nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = inputName.isEmpty ? (extensions.count == 1 ? ".\(extensions[0].uppercased()) 文件" : "自定义格式组") : inputName
                let commit = { [weak self] in
                    guard let self else { return }
                    do {
                        let group = try self.model.saveGroup(name: name, extensions: extensions, editing: existing?.id)
                        self.selectedHandlerID = group.id
                        self.reload(message: "已保存“\(name)”（\(extensions.count) 个后缀）。整组共用位置规则和“其他位置”应用；新增格式需启用自动打开。")
                    } catch {
                        self.reload(message: "保存失败：\(error.localizedDescription)", isError: true)
                    }
                }
                if let existing {
                    let retained = Set(extensions.compactMap { UTType(filenameExtension: $0)?.identifier })
                    let removed = existing.contentTypes.filter { !retained.contains($0.identifier) }
                    if !removed.isEmpty {
                        associationBusy = true
                        renderDetail(message: nil, isError: false)
                        model.restoreTypes(handler: existing, types: removed) { [weak self] result in
                            Task { @MainActor in
                                guard let self else { return }
                                self.associationBusy = false
                                switch result {
                                case .success(true): commit()
                                case .success(false):
                                    self.reload(message: "未修改格式组：部分移除格式无法恢复原应用。请先停用自动打开后重试。", isError: true)
                                case .failure(let error):
                                    self.reload(message: "未修改格式组：\(error.localizedDescription)", isError: true)
                                }
                            }
                        }
                        return
                    }
                }
                commit()
                return
            case .alertThirdButtonReturn:
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = true
                panel.message = "选择示例文件，将它们的后缀加入当前格式组"
                guard panel.runModal() == .OK else { continue }
                let extensions = panel.urls.map(\.pathExtension).filter { !$0.isEmpty }
                if extensions.isEmpty {
                    alert.informativeText = "所选文件没有后缀，请选择其他文件或手动输入。"
                } else {
                    let current = draft.extensionsField.stringValue
                    draft.extensionsField.stringValue = ([current] + extensions).filter { !$0.isEmpty }.joined(separator: ", ")
                }
            default: return
            }
        }
    }

    @objc private func chooseExampleFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择一个示例文件，OpenBy 会自动识别它的文件类型"
        panel.prompt = "使用这个文件类型"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addFileType(from: url)
    }

    private func addFileType(from url: URL) {
        guard !associationBusy else { return }
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else {
            reload(message: "无法识别这个文件的类型。请选择带有扩展名的文件。", isError: true)
            NSSound.beep()
            return
        }
        addFileType(extension: ext)
    }

    @discardableResult
    private func addFileType(extension ext: String) -> Bool {
        guard !associationBusy else { return false }
        guard let handler = model.addHandler(extension: ext) else {
            if let existing = model.conflictingHandler(extensions: [ext]) {
                selectedHandlerID = existing.id
                reload(message: ".\(ext) 文件已经在左侧列表中。")
                return true
            } else {
                reload(message: "macOS 无法识别 .\(ext) 文件类型。", isError: true)
            }
            return false
        }
        selectedHandlerID = handler.id
        reload(message: "已添加 .\(ext) 文件。下一步可以添加位置规则，再启用自动打开。")
        return true
    }

    @objc private func toggleManaged(_ sender: Any?) {
        guard !associationBusy, let handler = currentHandler,
              let type = UTType(handler.contentTypeIdentifier) else { return }

        if isManaged(handler) || (sender as? NSMenuItem)?.action == #selector(stopGroup(_:)) {
            associationBusy = true
            renderDetail(message: nil, isError: false)
            model.restoreDefault(handlerID: handler.id, contentType: type) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.associationBusy = false
                    switch result {
                    case .success(true):
                        self.reload(message: "自动打开已停用，原来的默认应用已经恢复。")
                    case .success(false):
                        self.reload(message: "无法恢复原来的应用。请先在 Finder 的“显示简介”中更改默认打开应用。", isError: true)
                    case .failure(let error):
                        self.reload(message: "停用失败：\(error.localizedDescription)", isError: true)
                    }
                }
            }
        } else {
            guard !handler.fallbackApplication.bundleIdentifier.isEmpty else {
                reload(message: "请先设置“其他位置”使用的应用，再启用自动打开。", isError: true)
                return
            }
            associationBusy = true
            renderDetail(message: nil, isError: false)
            model.takeOver(handlerID: handler.id, contentType: type) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.associationBusy = false
                    switch result {
                    case .success(true):
                        self.reload(message: "“\(self.typeDisplayName(handler))”的自动打开已全部启用。")
                    case .success(false):
                        self.reload(message: "尚未全部启用。请在 macOS 弹窗中允许后重试；已启用的格式会保留。", isError: true)
                    case .failure(let error):
                        self.reload(message: "启用失败：\(error.localizedDescription)", isError: true)
                    }
                }
            }
        }
    }

    @objc private func stopGroup(_ sender: Any?) {
        toggleManaged(sender)
    }

    @objc private func removeFileType(_ sender: Any?) {
        guard !associationBusy, let handler = currentHandler else { return }
        let ext = typeDisplayName(handler)
        let managed = model.managedCount(handler) > 0

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "移除“\(ext)”？"
        alert.informativeText = managed
            ? "OpenBy 会先恢复原来的默认应用，再删除这里的位置规则。"
            : "这会删除该格式组的所有位置规则，不会更改 macOS 当前的默认应用。"
        alert.addButton(withTitle: managed ? "恢复并移除" : "移除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let finishRemoval = { [weak self] in
            guard let self else { return }
            self.model.removeHandler(id: handler.id)
            self.selectedHandlerID = nil
            self.reload()
        }

        guard managed, let type = UTType(handler.contentTypeIdentifier) else {
            finishRemoval()
            return
        }

        associationBusy = true
        renderDetail(message: nil, isError: false)
        model.restoreDefault(handlerID: handler.id, contentType: type) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.associationBusy = false
                switch result {
                case .success(true):
                    finishRemoval()
                case .success(false):
                    self.reload(message: "没有删除：无法安全恢复原来的默认应用。请先停用自动打开。", isError: true)
                case .failure(let error):
                    self.reload(message: "没有删除：\(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    // MARK: - 规则

    @objc private func addRule(_ sender: Any?) {
        presentRuleEditor(existing: nil)
    }

    @objc private func editRule(_ sender: Any?) {
        guard let handler = currentHandler else { return }
        let row = (sender as? NSControl)?.tag ?? ruleTable.selectedRow
        let index = (sender as? NSTableView) === ruleTable ? ruleTable.clickedRow : row
        guard handler.rules.indices.contains(index) else { return }
        presentRuleEditor(existing: handler.rules[index])
    }

    private func presentRuleEditor(existing: FolderRule?) {
        guard let handler = currentHandler, let window = view.window, editorSession == nil else { return }
        let session = RuleEditorSession(handler: handler, existing: existing)
        editorSession = session
        session.present(on: window) { [weak self] rule in
            guard let self else { return }
            self.editorSession = nil
            guard let rule else { return }
            if let existing {
                self.model.updateRule(handlerID: handler.id, ruleID: existing.id) { $0 = rule }
            } else {
                self.model.updateHandler(id: handler.id) { $0.rules.append(rule) }
            }
            self.reload(message: existing == nil ? "位置规则已添加。" : "位置规则已更新。")
        }
    }

    @objc private func ruleMenuAction(_ sender: NSMenuItem) {
        guard let handler = currentHandler else { return }
        let row = sender.tag / 10
        guard handler.rules.indices.contains(row) else { return }
        ruleTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        switch sender.tag % 10 {
        case 1:
            model.moveRule(handlerID: handler.id, from: row, to: row - 1)
        case 2:
            model.moveRule(handlerID: handler.id, from: row, to: row + 1)
        case 3:
            let rule = handler.rules[row]
            model.updateRule(handlerID: handler.id, ruleID: rule.id) { $0.enabled.toggle() }
        default:
            deleteRule(nil)
            return
        }
        reload(message: "位置规则已更新。")
    }

    @objc private func deleteRule(_ sender: Any?) {
        guard let handler = currentHandler else { return }
        let row = ruleTable.selectedRow
        guard row >= 0, row < handler.rules.count else { return }
        let rule = handler.rules[row]

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "移除这条位置规则？"
        alert.informativeText = ruleSummary(rule)
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        model.removeRule(handlerID: handler.id, ruleID: rule.id)
        reload(message: "位置规则已移除。")
    }

    @objc private func changeFallback(_ sender: Any?) {
        guard let handler = currentHandler else { return }
        guard let url = chooseApplication(message: "选择没有匹配到位置规则时使用的应用") else { return }
        let reference = SettingsModel.applicationReference(from: url)
        model.updateHandler(id: handler.id) { $0.fallbackApplication = reference }
        reload(message: "其他位置现在会使用 \(reference.displayName) 打开。")
    }

    private func chooseApplication(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.message = message
        panel.prompt = "选择应用"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func ruleSummary(_ rule: FolderRule) -> String {
        let scope = rule.includesDescendants ? "及其子文件夹" : "中的文件"
        return "“\(folderDisplayName(rule.folderPath))”\(scope) → \(rule.targetApplication.displayName)"
    }

    private func folderDisplayName(_ path: String) -> String {
        let expanded = PathInput.expandedAbsolutePath(path)
        let name = URL(fileURLWithPath: expanded).lastPathComponent
        return name.isEmpty ? expanded : name
    }

    // MARK: - Table data source / delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === handlerTable { return model.configuration.handlers.count }
        return currentHandler?.rules.count ?? 0
    }

    private func typeDisplayName(_ handler: FileHandler) -> String {
        if let name = handler.groupName { return name }
        switch handler.displayExtensions.first?.lowercased() {
        case "pdf": return "PDF 文档"
        case "md", "markdown": return "Markdown"
        case "txt": return "文本文件"
        default: return (handler.displayExtensions.first?.uppercased() ?? "未知类型") + " 文件"
        }
    }

    private func applicationIcon(_ reference: ApplicationReference) -> NSImage? {
        guard let url = model.resolver.applicationURL(for: reference) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "应用不可用")
        }
        let key = url.path as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache.countLimit = 64
        iconCache.setObject(icon, forKey: key)
        return icon
    }

    private func rebuildTypeMenu(managed: Bool) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "更多", action: nil, keyEquivalent: "")
        title.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "更多")
        menu.addItem(title)
        let edit = NSMenuItem(title: "编辑格式组…", action: #selector(editFormatGroup(_:)), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        menu.addItem(.separator())
        if managed {
            let stop = NSMenuItem(title: "停用并恢复原应用…", action: #selector(stopGroup(_:)), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
            menu.addItem(.separator())
        }
        let remove = NSMenuItem(title: "移除格式组…", action: #selector(removeFileType(_:)), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        moreButton.menu = menu
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === handlerTable {
            guard row < model.configuration.handlers.count else { return nil }
            let handler = model.configuration.handlers[row]
            let identifier = NSUserInterfaceItemIdentifier("handlerCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? SettingsTypeCell ?? SettingsTypeCell()
            cell.identifier = identifier
            cell.name.stringValue = typeDisplayName(handler)
            cell.subtitle.stringValue = "\(handler.displayExtensions.count) 个后缀 · \(model.managedCount(handler) == 0 ? "尚未启用" : (isManaged(handler) ? "已启用" : "部分启用"))"
            cell.icon.image = UTType(handler.contentTypeIdentifier).map { NSWorkspace.shared.icon(for: $0) }
            cell.toolTip = cell.name.stringValue + " · " + cell.subtitle.stringValue
            return cell
        }
        guard let handler = currentHandler, row < handler.rules.count else { return nil }
        let rule = handler.rules[row]
        let identifier = NSUserInterfaceItemIdentifier("ruleCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? SettingsRuleCell ?? SettingsRuleCell()
        cell.identifier = identifier
        cell.order.stringValue = String(row + 1)
        cell.folder.stringValue = folderDisplayName(rule.folderPath)
        let folderExists = FileManager.default.fileExists(atPath: PathInput.expandedAbsolutePath(rule.folderPath))
        let appExists = model.resolver.applicationURL(for: rule.targetApplication) != nil
        let issue = !folderExists ? "文件夹不可用" : (!appExists ? "应用不可用" : "")
        cell.path.stringValue = (rule.folderPath as NSString).abbreviatingWithTildeInPath
        cell.path.toolTip = rule.folderPath
        cell.scope.stringValue = (rule.enabled ? "" : "已关闭 · ") + (issue.isEmpty ? (rule.includesDescendants ? "包含子文件夹" : "仅当前文件夹") : "⚠ " + issue)
        cell.scope.textColor = issue.isEmpty ? .secondaryLabelColor : .systemOrange
        cell.appName.stringValue = rule.targetApplication.displayName
        cell.appName.toolTip = rule.targetApplication.displayName
        cell.appIcon.image = applicationIcon(rule.targetApplication)
        cell.folder.textColor = rule.enabled ? .labelColor : .secondaryLabelColor
        cell.appName.textColor = rule.enabled ? .labelColor : .secondaryLabelColor
        cell.edit.tag = row
        cell.edit.target = self
        cell.edit.action = #selector(editRule(_:))
        cell.edit.setAccessibilityLabel("编辑第 \(row + 1) 条规则：\(cell.folder.stringValue)")
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "更多", action: nil, keyEquivalent: "")
        title.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        menu.addItem(title)
        for (offset, name) in [(1, "上移"), (2, "下移"), (3, rule.enabled ? "关闭规则" : "开启规则"), (4, "移除规则…")] {
            let item = NSMenuItem(title: name, action: #selector(ruleMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = row * 10 + offset
            item.isEnabled = !(offset == 1 && row == 0) && !(offset == 2 && row == handler.rules.count - 1)
            menu.addItem(item)
        }
        cell.more.menu = menu
        cell.more.setAccessibilityLabel("第 \(row + 1) 条规则的更多操作")
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        if table === handlerTable {
            let row = handlerTable.selectedRow
            if row >= 0, row < model.configuration.handlers.count {
                selectedHandlerID = model.configuration.handlers[row].id
                renderDetail(message: nil, isError: false)
            }
        }
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard tableView === ruleTable,
              row >= 0,
              row < (currentHandler?.rules.count ?? 0) else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.ruleDragType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        if tableView === handlerTable {
            guard let url = NSURL(from: info.draggingPasteboard) as URL?, !url.hasDirectoryPath else {
                return []
            }
            return .copy
        }
        guard (info.draggingSource as? NSTableView) === ruleTable, dropOperation == .above else { return [] }
        let count = currentHandler?.rules.count ?? 0
        tableView.setDropRow(min(row, count), dropOperation: .above)
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        if tableView === handlerTable {
            guard let url = NSURL(from: info.draggingPasteboard) as URL? else { return false }
            addFileType(from: url)
            return true
        }
        guard let handler = currentHandler,
              let value = info.draggingPasteboard.string(forType: Self.ruleDragType),
              let source = Int(value),
              source >= 0, source < handler.rules.count,
              (info.draggingSource as? NSTableView) === ruleTable else { return false }
        model.moveRule(handlerID: handler.id, from: source, to: min(row > source ? row - 1 : row, handler.rules.count - 1))
        reload(message: "规则顺序已更新。")
        return true
    }
}

/// 可接收示例文件的主内容容器。
@MainActor
private final class DropTargetView: NSView {
    var onFileDrop: ((URL) -> Void)?
    private var highlightsDrop = false {
        didSet {
            wantsLayer = true
            layer?.borderWidth = highlightsDrop ? 3 : 0
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.cornerRadius = 8
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let url = NSURL(from: sender.draggingPasteboard) as URL?, !url.hasDirectoryPath else { return [] }
        highlightsDrop = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { highlightsDrop = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlightsDrop = false
        guard let url = NSURL(from: sender.draggingPasteboard) as URL?, !url.hasDirectoryPath else {
            return false
        }
        onFileDrop?(url)
        return true
    }
}

/// 规则编辑会话。用自然语言预览把“路径 + 递归 + 应用”解释成一个结果。
@MainActor
private final class RuleEditorSession: NSObject {
    private let handler: FileHandler
    private let existing: FolderRule?
    private let folderField = NSTextField(string: "")
    private let applicationLabel = NSTextField(labelWithString: "尚未选择应用")
    private let descendantsButton = NSButton(checkboxWithTitle: "同时应用于子文件夹", target: nil, action: nil)
    private let enabledButton = NSButton(checkboxWithTitle: "开启这条规则", target: nil, action: nil)
    private let previewLabel = NSTextField(wrappingLabelWithString: "")
    private var targetApplication: ApplicationReference

    init(handler: FileHandler, existing: FolderRule?) {
        self.handler = handler
        self.existing = existing
        self.targetApplication = existing?.targetApplication ?? handler.fallbackApplication
        super.init()
    }

    private var sheet: NSWindow?
    private var completion: ((FolderRule?) -> Void)?
    private let saveButton = NSButton(title: "保存规则", target: nil, action: nil)

    func present(on parent: NSWindow, completion: @escaping (FolderRule?) -> Void) {
        self.completion = completion
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 430), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = existing == nil ? "添加位置规则" : "编辑位置规则"
        window.isReleasedWhenClosed = false
        sheet = window
        let title = SettingsStyle.label(window.title, size: 20, weight: .semibold)
        let description = SettingsStyle.label("设置 \(handler.displayExtensions.map { "." + $0 }.joined(separator: " / ")) 文件在这个位置时使用的应用。", size: 12, color: .secondaryLabelColor)
        description.lineBreakMode = .byTruncatingTail
        folderField.stringValue = existing?.folderPath ?? ""
        folderField.placeholderString = "请选择文件夹"
        folderField.isEditable = false
        folderField.isSelectable = true
        folderField.lineBreakMode = .byTruncatingMiddle
        folderField.setAccessibilityLabel("规则文件夹路径")
        folderField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let chooseFolder = NSButton(title: "选择文件夹…", target: self, action: #selector(chooseFolder(_:)))
        SettingsStyle.button(chooseFolder, symbol: "folder")
        let folderRow = SettingsStyle.row([folderField, chooseFolder])
        descendantsButton.state = (existing?.includesDescendants ?? true) ? .on : .off
        descendantsButton.target = self
        descendantsButton.action = #selector(updatePreview(_:))
        applicationLabel.stringValue = targetApplication.bundleIdentifier.isEmpty ? "尚未选择应用" : targetApplication.displayName
        applicationLabel.lineBreakMode = .byTruncatingMiddle
        applicationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let chooseApp = NSButton(title: "选择应用…", target: self, action: #selector(chooseApplication(_:)))
        SettingsStyle.button(chooseApp, symbol: "app")
        let appRow = SettingsStyle.row([applicationLabel, SettingsStyle.spacer(), chooseApp])
        enabledButton.state = (existing?.enabled ?? true) ? .on : .off
        previewLabel.font = .systemFont(ofSize: 12)
        previewLabel.maximumNumberOfLines = 0
        previewLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelEditing(_:)))
        SettingsStyle.button(cancel)
        cancel.keyEquivalent = "\u{1b}"
        SettingsStyle.button(saveButton)
        saveButton.bezelColor = .controlAccentColor
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(saveEditing(_:))
        let content = SettingsStyle.column([
            SettingsStyle.column([title, description], spacing: 6),
            SettingsStyle.column([SettingsStyle.label("文件所在文件夹", size: 13, weight: .medium), folderRow, descendantsButton], spacing: 10),
            SettingsStyle.column([SettingsStyle.label("使用此应用打开", size: 13, weight: .medium), appRow, enabledButton], spacing: 10),
            SettingsStyle.group(previewLabel),
            SettingsStyle.row([SettingsStyle.spacer(), cancel, saveButton]),
        ], spacing: 24)
        guard let container = window.contentView else { return }
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
        ])
        updatePreview(nil)
        window.setContentSize(NSSize(width: 520, height: max(430, content.fittingSize.height + 48)))
        parent.beginSheet(window)
    }

    @objc private func cancelEditing(_ sender: Any?) { finish(nil) }

    @objc private func saveEditing(_ sender: Any?) {
        guard saveButton.isEnabled else { return }
        finish(FolderRule(
            id: existing?.id ?? UUID(),
            enabled: enabledButton.state == .on,
            folderPath: PathInput.expandedAbsolutePath(folderField.stringValue),
            includesDescendants: descendantsButton.state == .on,
            targetApplication: targetApplication
        ))
    }

    private func finish(_ rule: FolderRule?) {
        if let sheet { sheet.sheetParent?.endSheet(sheet); sheet.orderOut(nil) }
        let callback = completion
        completion = nil
        callback?(rule)
    }

    @objc private func chooseFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择这条规则适用的文件夹"
        panel.prompt = "选择文件夹"
        if !folderField.stringValue.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: PathInput.expandedAbsolutePath(folderField.stringValue))
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderField.stringValue = url.path
        updatePreview(nil)
    }

    @objc private func chooseApplication(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.message = "选择符合这条位置规则时使用的应用"
        panel.prompt = "选择应用"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        targetApplication = SettingsModel.applicationReference(from: url)
        applicationLabel.stringValue = targetApplication.displayName
        updatePreview(nil)
    }

    @objc private func updatePreview(_ sender: Any?) {
        let rawPath = folderField.stringValue
        let folder = rawPath.isEmpty
            ? "所选文件夹"
            : URL(fileURLWithPath: PathInput.expandedAbsolutePath(rawPath)).lastPathComponent
        let scope = descendantsButton.state == .on ? "包含子文件夹" : "仅当前文件夹"
        let app = targetApplication.bundleIdentifier.isEmpty ? "所选应用" : targetApplication.displayName
        let validFolder = !PathInput.expandedAbsolutePath(rawPath).isEmpty
        let validApp = !targetApplication.bundleIdentifier.isEmpty && targetApplication.bundleIdentifier != Bundle.main.bundleIdentifier
        saveButton.isEnabled = validFolder && validApp
        folderField.toolTip = rawPath
        applicationLabel.toolTip = applicationLabel.stringValue
        previewLabel.textColor = .secondaryLabelColor
        if !validFolder {
            previewLabel.stringValue = "请选择这条规则适用的文件夹。"
            return
        }
        if !validApp {
            previewLabel.stringValue = "请选择用于打开文件的应用，不能选择 OpenBy 自身。"
            return
        }
        previewLabel.stringValue = "“\(folder)”中的文件将使用 \(app) 打开（\(scope)）。"
    }
}


/// 编辑草稿不触碰配置；预设只是填充名称与可修改的后缀列表。
@MainActor
private final class FormatGroupDraft: NSObject {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
    let nameField = NSTextField()
    let extensionsField = NSTextField()
    private let preset = NSPopUpButton(frame: .zero, pullsDown: false)

    init(existing: FileHandler?) {
        super.init()
        preset.addItem(withTitle: "自定义")
        preset.addItems(withTitles: FormatGroups.presets.map(\.name))
        preset.target = self
        preset.action = #selector(selectPreset(_:))
        nameField.placeholderString = "组名（可选），例如：工作图片"
        nameField.stringValue = existing?.groupName ?? ""
        nameField.setAccessibilityLabel("格式组名称")
        extensionsField.placeholderString = "例如：jpg, png, webp"
        extensionsField.stringValue = existing?.displayExtensions.joined(separator: ", ") ?? ""
        extensionsField.setAccessibilityLabel("组内文件后缀，可增删")
        extensionsField.cell?.wraps = true
        extensionsField.cell?.isScrollable = false
        extensionsField.usesSingleLineMode = false
        let hint = SettingsStyle.label("用逗号或空格分隔；删除后缀即可将它排除。", size: 11, color: .secondaryLabelColor)
        let stack = SettingsStyle.column([
            SettingsStyle.label("预设"), preset,
            SettingsStyle.label("组名"), nameField,
            SettingsStyle.label("组内后缀（可编辑）"), extensionsField, hint,
        ], spacing: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            extensionsField.heightAnchor.constraint(equalToConstant: 64),
        ])
    }

    @objc private func selectPreset(_ sender: Any?) {
        let index = preset.indexOfSelectedItem - 1
        guard FormatGroups.presets.indices.contains(index) else { return }
        let selected = FormatGroups.presets[index]
        nameField.stringValue = selected.name
        extensionsField.stringValue = selected.extensions.joined(separator: ", ")
    }
}
