import AppKit
import QuartzCore
import UniformTypeIdentifiers

/// Shared native presentation primitives. Colors follow the window's effective appearance.
@MainActor
enum SettingsStyle {
    static let cornerRadius: CGFloat = 8

    static func isMouseInside(_ view: NSView) -> Bool {
        guard let window = view.window, window.isVisible, window.isKeyWindow,
              window.attachedSheet == nil, !view.isHiddenOrHasHiddenAncestor,
              !view.visibleRect.isEmpty else { return false }
        let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return view.visibleRect.contains(point)
    }

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
        box.borderWidth = 0
        box.cornerRadius = 10
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.masksToBounds = true
        box.borderColor = .separatorColor
        box.isTransparent = true
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

/// Keep native button sizing, actions and keyboard behavior, with a shared modest radius.
@MainActor
final class SettingsButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var hoverRefreshPending = false
    private var pointerInside = false {
        didSet { if pointerInside != oldValue { needsDisplay = true } }
    }
    var isHovered: Bool {
        pointerInside && window?.isKeyWindow == true && window?.isVisible == true
            && window?.attachedSheet == nil && !isHiddenOrHasHiddenAncestor
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = SettingsButtonCell(textCell: "")
        isBordered = true
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(refreshHover), name: name, object: nil)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }
    deinit { NotificationCenter.default.removeObserver(self) }
    // NSCell may temporarily change the control's coordinate system while drawing.
    // Resolve pointer geometry after layout, never from drawBezel/drawTitle.
    @objc private func refreshHover() {
        needsDisplay = true
        guard !hoverRefreshPending else { return }
        hoverRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hoverRefreshPending = false
            self.pointerInside = SettingsStyle.isMouseInside(self)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
        refreshHover()
    }

    override func mouseEntered(with event: NSEvent) { refreshHover() }
    override func mouseExited(with event: NSEvent) { pointerInside = false }
    override func layout() { super.layout(); refreshHover() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pointerInside = false
        refreshHover()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor
private final class SettingsButtonCell: NSButtonCell {
    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        let outline = NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1),
                                   xRadius: SettingsStyle.cornerRadius, yRadius: SettingsStyle.cornerRadius)
        let bezelColor = (controlView as? NSButton)?.bezelColor
        let emphasized = bezelColor != nil || keyEquivalent == "\r"
        let color = emphasized ? (bezelColor ?? .controlAccentColor) : NSColor.controlColor
        color.withAlphaComponent(isEnabled ? 1 : 0.3).setFill()
        outline.fill()
        if !emphasized {
            NSColor.labelColor.withAlphaComponent(isEnabled ? 0.045 : 0.02).setFill()
            outline.fill()
        }
        let hovered = (controlView as? SettingsButton)?.isHovered == true
            && controlView.window?.isKeyWindow == true && isEnabled
        if hovered && !isHighlighted {
            (emphasized ? NSColor.white : NSColor.controlAccentColor)
                .withAlphaComponent(emphasized ? 0.14 : 0.08).setFill()
            outline.fill()
            (emphasized ? NSColor.white : NSColor.controlAccentColor)
                .withAlphaComponent(emphasized ? 0.28 : 0.3).setStroke()
            outline.lineWidth = 1
            outline.stroke()
        }
        if isHighlighted {
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            outline.fill()
        }
    }

    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let styled = NSMutableAttributedString(attributedString: title)
        let bezelColor = (controlView as? NSButton)?.bezelColor
        let emphasized = bezelColor != nil || keyEquivalent == "\r"
        let color: NSColor = !isEnabled ? .disabledControlTextColor : (emphasized ? .white : .labelColor)
        styled.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: styled.length))
        return super.drawTitle(styled, withFrame: frame, in: controlView)
    }

    override func drawFocusRingMask(withFrame frame: NSRect, in controlView: NSView) {
        NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1),
                     xRadius: SettingsStyle.cornerRadius, yRadius: SettingsStyle.cornerRadius).fill()
    }
}

@MainActor
private final class SettingsBackgroundView: NSView {
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor
final class SettingsFlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class SettingsTypeTable: NSTableView {
    private func refreshRows() {
        enumerateAvailableRowViews { row, _ in row.needsDisplay = true }
    }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        refreshRows()
        return result
    }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        refreshRows()
        return result
    }
}

@MainActor
private final class SettingsTypeRow: NSTableRowView {
    private var hover = false
    private var tracking: NSTrackingArea?
    private var transition: Timer?
    private var backgroundAlpha: CGFloat = 0
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override var isSelected: Bool { didSet { refresh() } }
    override var isEmphasized: Bool { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSWindow.didResignKeyNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSColor.systemColorsDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }
    deinit { NotificationCenter.default.removeObserver(self); transition?.invalidate() }
    @objc private func refresh() {
        transition?.invalidate()
        let active = window?.isKeyWindow == true
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let target: CGFloat = isSelected
            ? (active ? (dark ? 0.24 : 0.12) : (dark ? 0.13 : 0.07))
            : (hover && active ? 0.05 : 0)
        let initial = backgroundAlpha
        let started = CACurrentMediaTime()
        needsDisplay = true
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            backgroundAlpha = target
            return
        }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let progress = min(1, (CACurrentMediaTime() - started) / 0.12)
                self.backgroundAlpha = initial + (target - initial) * progress
                self.needsDisplay = true
                if progress >= 1 { timer.invalidate() }
            }
        }
        transition = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        hover = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        refresh()
    }
    override func mouseEntered(with event: NSEvent) { hover = true; refresh() }
    override func mouseExited(with event: NSEvent) { hover = false; refresh() }
    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawBackground(in dirtyRect: NSRect) {}
    override func draw(_ dirtyRect: NSRect) {
        let active = window?.isKeyWindow == true
        let accent = NSColor.controlAccentColor
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 2.5, dy: 2.5), xRadius: SettingsStyle.cornerRadius, yRadius: SettingsStyle.cornerRadius)
        (isSelected ? accent : NSColor.labelColor).withAlphaComponent(backgroundAlpha).setFill()
        outline.fill()
        if isSelected {
            accent.withAlphaComponent(active ? 1 : 0.5).setFill()
            NSBezierPath(roundedRect: NSRect(x: 6, y: bounds.midY - 9, width: 3, height: 18), xRadius: 1.5, yRadius: 1.5).fill()
            if (active && window?.firstResponder === superview) || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
                accent.withAlphaComponent(0.8).setStroke()
                outline.lineWidth = 1
                outline.stroke()
            }
        }
        for case let cell as SettingsTypeCell in subviews {
            cell.name.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium)
        }
    }
}

@MainActor
private final class SettingsTypeCell: NSTableCellView {
    let name = SettingsStyle.label("", weight: .medium)
    let subtitle = SettingsStyle.label("", size: 11, color: .secondaryLabelColor)
    let icon = NSImageView()

    func setStatus(count: Int, managed: Int, fullyManaged: Bool) {
        let state = managed == 0 ? "尚未启用" : (fullyManaged ? "已启用" : "部分启用")
        let color = NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if managed == 0 { return dark ? .systemRed : NSColor(srgbRed: 0.72, green: 0.16, blue: 0.18, alpha: 1) }
            if fullyManaged { return dark ? .systemGreen : NSColor(srgbRed: 0.13, green: 0.43, blue: 0.23, alpha: 1) }
            return dark ? .systemOrange : NSColor(srgbRed: 0.62, green: 0.32, blue: 0.02, alpha: 1)
        }
        let text = NSMutableAttributedString(string: "\(count) 个后缀  ", attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        text.append(NSAttributedString(string: "● \(state)", attributes: [.foregroundColor: color]))
        subtitle.attributedStringValue = text
        setAccessibilityLabel("\(name.stringValue)，\(count) 个后缀，\(state)")
    }

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
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }
}

private enum SettingsRuleAction: Int {
    case edit, toggle, delete
}

/// The handle leaves mouse events with the table so AppKit owns selection and reordering.
@MainActor
private final class SettingsRuleDragHandle: NSView {
    private var tracking: NSTrackingArea?
    private var hovered = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "拖动调整规则顺序"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        hovered = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func draw(_ dirtyRect: NSRect) {
        (hovered ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setFill()
        for offset: CGFloat in [-5, 0, 5] {
            NSBezierPath(roundedRect: NSRect(x: bounds.midX - 7, y: bounds.midY + offset - 1,
                                            width: 14, height: 2), xRadius: 1, yRadius: 1).fill()
        }
    }
}

@MainActor
private final class SettingsRuleRow: NSTableRowView {
    private var tracking: NSTrackingArea?
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(refreshHover), name: name, object: nil)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func refreshHover() { needsDisplay = true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        needsDisplay = true
    }
    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 4, dy: 5)
        let outline = NSBezierPath(roundedRect: rect, xRadius: SettingsStyle.cornerRadius, yRadius: SettingsStyle.cornerRadius)
        NSColor.controlBackgroundColor.setFill()
        outline.fill()
        NSColor.labelColor.withAlphaComponent(0.025).setFill()
        outline.fill()
        if SettingsStyle.isMouseInside(self) {
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
            outline.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.35).setStroke()
            outline.lineWidth = 1
            outline.stroke()
        }
    }
    override func drawSelection(in dirtyRect: NSRect) {}
}

@MainActor
private final class SettingsRuleCell: NSTableCellView {
    static let rowHeight: CGFloat = 94
    let dragHandle = SettingsRuleDragHandle()
    let folder = SettingsStyle.label("", weight: .medium)
    let path = SettingsStyle.label("", size: 11, color: .secondaryLabelColor)
    let scope = SettingsStyle.label("", size: 11, color: .secondaryLabelColor)
    let appName = SettingsStyle.label("", size: 12, weight: .medium)
    let appIcon = NSImageView()
    let edit = SettingsButton(title: "编辑", target: nil, action: nil)
    let more = SettingsButton(title: "⋮", target: nil, action: nil)
    var ruleEnabled = true
    var ruleID: UUID?
    var onAction: ((UUID, SettingsRuleAction) -> Void)?

    @objc private func performAction(_ sender: NSButton) {
        guard let ruleID else { return }
        onAction?(ruleID, .edit)
    }

    @objc private func showMoreMenu(_ sender: NSButton) {
        guard let ruleID, sender.isEnabled else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, action) in [(ruleEnabled ? "停用" : "启用", SettingsRuleAction.toggle), ("删除…", .delete)] {
            let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = action.rawValue
            item.representedObject = ruleID
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let action = SettingsRuleAction(rawValue: sender.tag) else { return }
        onAction?(id, action)
    }

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
        SettingsStyle.size(dragHandle, 24)
        let location = SettingsStyle.column([SettingsStyle.row([folderIcon, folder], spacing: 6), path, scope], spacing: 3)
        location.setContentHuggingPriority(.init(1), for: .horizontal)
        location.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let application = SettingsStyle.row([appIcon, appName], spacing: 8)
        application.widthAnchor.constraint(equalToConstant: 140).isActive = true
        SettingsStyle.button(edit)
        edit.target = self
        edit.action = #selector(performAction(_:))
        more.isBordered = false
        more.font = .systemFont(ofSize: 20, weight: .medium)
        more.toolTip = "更多操作"
        SettingsStyle.size(more, 28)
        more.target = self
        more.action = #selector(showMoreMenu(_:))
        let arrow = SettingsStyle.label("→", color: .secondaryLabelColor)
        arrow.widthAnchor.constraint(equalToConstant: 14).isActive = true
        let actions = SettingsStyle.row([edit, more], spacing: 8)
        let row = SettingsStyle.row([dragHandle, location, arrow, application, actions], spacing: 8)
        row.setCustomSpacing(16, after: application)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
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
    private static let defaultContentSize = NSSize(width: 1000, height: 680)
    private let contentController: SettingsWorkspaceViewController
    private var didBuildContent = false

    init(model: SettingsModel) {
        contentController = SettingsWorkspaceViewController(model: model)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
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
            // Auto Layout derives window limits from content constraints and ignores minSize.
            if let window {
                let minimumContent = window.contentRect(forFrameRect: NSRect(origin: .zero, size: window.minSize)).size
                NSLayoutConstraint.activate([
                    contentController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumContent.width),
                    contentController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumContent.height),
                ])
            }
            window?.setContentSize(Self.defaultContentSize)
            window?.center()
            didBuildContent = true
        }
        contentController.reload()
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        showWindow(nil)
    }

    func reloadFromModel() {
        contentController.reload()
    }

    func focus(handlerID: UUID) {
        show()
        contentController.focus(handlerID: handlerID)
    }
}

/// 单窗口主从界面：左侧选择文件类型，右侧完成启用、规则和未匹配规则时。
@MainActor
private final class SettingsWorkspaceViewController: NSViewController,
    NSTableViewDataSource,
    NSTableViewDelegate
{
    private let model: SettingsModel

    private let sidebar = NSView()
    private let sidebarTitle = NSTextField(labelWithString: "文件类型")
    private let handlerTable = SettingsTypeTable()
    private let handlerScroll = NSScrollView()
    private let addTypeButton = SettingsButton(title: "添加文件类型", target: nil, action: nil)

    private let detailContainer = DropTargetView()
    private let emptyView = NSView()
    private let detailView = SettingsFlippedView()
    private let detailScroll = NSScrollView()
    private let typeIcon = NSImageView()
    private let typeSubtitle = NSTextField(labelWithString: "")
    private let fallbackIcon = NSImageView()
    private let editTypeButton = SettingsButton(title: "编辑类型", target: nil, action: nil)
    private let removeTypeButton = SettingsButton(title: "移除类型", target: nil, action: nil)
    private var ruleHeight: NSLayoutConstraint!
    private var editorSession: RuleEditorSession?
    private var associationBusy = false
    private let iconCache = NSCache<NSString, NSImage>()
    private static let ruleDragType = NSPasteboard.PasteboardType("app.openby.rule-row")
    private let emptyFeedback = NSTextField(wrappingLabelWithString: "")

    private let typeTitle = NSTextField(labelWithString: "")
    private let statusDot = NSTextField(labelWithString: "●")
    private let statusLabel = NSTextField(labelWithString: "")
    private let enableButton = SettingsButton(title: "", target: nil, action: nil)

    private let rulesTitle = NSTextField(labelWithString: "按文件所在位置选择应用")
    private let rulesExplanation = NSTextField(labelWithString: "如果一个文件同时符合多条规则，将优先使用排在上面的规则。")
    private let ruleTable = NSTableView()
    private let ruleScroll = NSScrollView()
    private let rulesEmptyLabel = NSTextField(labelWithString: "还没有文件夹规则。添加一条规则，让特定文件夹里的文件使用指定应用打开。")
    private let addRuleButton = SettingsButton(title: "添加文件夹规则", target: nil, action: nil)

    private let fallbackTitle = NSTextField(labelWithString: "未匹配规则时")
    private let fallbackDescription = NSTextField(labelWithString: "没有匹配到上方规则时，使用：")
    private let fallbackApplication = NSTextField(labelWithString: "")
    private let changeFallbackButton = SettingsButton(title: "更换应用", target: nil, action: nil)

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
        view = SettingsBackgroundView()
        buildUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reload()
    }

    func focus(handlerID: UUID) {
        guard model.handler(id: handlerID) != nil else { return }
        selectedHandlerID = handlerID
        reload()
        if let index = model.configuration.handlers.firstIndex(where: { $0.id == handlerID }) {
            handlerTable.scrollRowToVisible(index)
        }
        detailScroll.contentView.scroll(to: .zero)
        detailScroll.reflectScrolledClipView(detailScroll.contentView)
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
        sidebarTitle.stringValue = "文件类型"
        sidebarTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        sidebarTitle.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("handler"))
        handlerTable.addTableColumn(column)
        handlerTable.headerView = nil
        handlerTable.style = .plain
        handlerTable.focusRingType = .none
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
        let addTypeRow = SettingsStyle.column([addTypeButton], spacing: 8)
        for child in [sidebarTitle, handlerScroll, addTypeRow] {
            child.translatesAutoresizingMaskIntoConstraints = false
            sidebar.addSubview(child)
        }
        NSLayoutConstraint.activate([
            sidebarTitle.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 22),
            sidebarTitle.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20),
            handlerScroll.topAnchor.constraint(equalTo: addTypeRow.bottomAnchor, constant: 12),
            handlerScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            handlerScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),
            handlerScroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -16),
            addTypeRow.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            addTypeRow.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            addTypeRow.topAnchor.constraint(equalTo: sidebarTitle.bottomAnchor, constant: 12),
        ])
    }

    private func buildEmptyState() {
        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 42, weight: .regular)
        icon.contentTintColor = .controlAccentColor

        let title = NSTextField(labelWithString: "按文件夹设置打开应用")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.alignment = .center

        let explanation = NSTextField(wrappingLabelWithString: "添加文件类型，为不同文件夹选择打开应用。可添加多个后缀，共用同一套规则。")
        explanation.textColor = .secondaryLabelColor
        explanation.alignment = .center
        explanation.maximumNumberOfLines = 3

        let steps = NSTextField(wrappingLabelWithString: "添加类型  →  设置规则  →  启用自动打开")
        steps.font = .systemFont(ofSize: 13, weight: .medium)
        steps.textColor = .secondaryLabelColor
        steps.maximumNumberOfLines = 3

        let chooseButton = SettingsButton(title: "添加文件类型", target: self, action: #selector(showAddFileType(_:)))
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
        for (button, action) in [(editTypeButton, #selector(editFormatGroup(_:))),
                                 (removeTypeButton, #selector(removeFileType(_:)))] {
            SettingsStyle.button(button)
            button.target = self
            button.action = action
        }
        let header = SettingsStyle.row([heading, SettingsStyle.spacer()])
        // Buttons resist stretching; the spacer lets this full-width row grow with the window.
        let typeActions = SettingsStyle.row([editTypeButton, enableButton, removeTypeButton, SettingsStyle.spacer()], spacing: 8)

        rulesTitle.stringValue = "文件夹规则"
        rulesTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        rulesExplanation.stringValue = "按顺序检查，使用第一条匹配的规则。可拖动规则调整顺序。"
        rulesExplanation.font = .systemFont(ofSize: 11)
        rulesExplanation.textColor = .secondaryLabelColor
        rulesExplanation.maximumNumberOfLines = 0
        rulesExplanation.cell?.wraps = true
        rulesExplanation.setContentCompressionResistancePriority(.required, for: .vertical)
        rulesEmptyLabel.stringValue = "还没有文件夹规则\n启用自动打开后，将使用下方应用。"
        rulesEmptyLabel.font = .systemFont(ofSize: 12)
        rulesEmptyLabel.textColor = .secondaryLabelColor
        rulesEmptyLabel.alignment = .center
        rulesEmptyLabel.maximumNumberOfLines = 2
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("route"))
        column.resizingMask = .autoresizingMask
        ruleTable.addTableColumn(column)
        ruleTable.headerView = nil
        ruleTable.style = .plain
        ruleTable.rowHeight = SettingsRuleCell.rowHeight
        ruleTable.focusRingType = .none
        ruleTable.intercellSpacing = .zero
        ruleTable.backgroundColor = .clear
        ruleScroll.drawsBackground = false
        ruleTable.dataSource = self
        ruleTable.delegate = self
        ruleTable.target = self
        ruleTable.doubleAction = #selector(editRule(_:))
        ruleTable.allowsMultipleSelection = false
        ruleTable.selectionHighlightStyle = .none
        ruleTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        ruleTable.setAccessibilityLabel("文件夹规则，按优先级排序")
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
        fallbackDescription.stringValue = "启用自动打开后，未匹配规则的文件使用此应用"
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
        let content = SettingsStyle.column([header, status, typeActions, rules, fallback, feedbackLabel], spacing: 24)
        content.setCustomSpacing(8, after: header)
        content.translatesAutoresizingMaskIntoConstraints = false
        detailView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: detailView.topAnchor, constant: 28),
            content.leadingAnchor.constraint(equalTo: detailView.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: detailView.trailingAnchor, constant: -20),
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
        let hasManagedFormats = model.managedCount(handler) > 0
        enableButton.title = associationBusy ? "正在更新" : (hasManagedFormats ? "关闭自动打开" : "启用自动打开")
        enableButton.isEnabled = !associationBusy
        enableButton.bezelColor = hasManagedFormats ? nil : .controlAccentColor
        addRuleButton.bezelColor = managed ? .controlAccentColor : nil
        editTypeButton.isEnabled = !associationBusy
        removeTypeButton.isEnabled = !associationBusy
        addRuleButton.isEnabled = !associationBusy
        changeFallbackButton.isEnabled = !associationBusy
        handlerTable.isEnabled = !associationBusy
        addTypeButton.isEnabled = !associationBusy
        enableButton.toolTip = hasManagedFormats
            ? "关闭自动打开，并恢复启用前的默认应用"
            : "让 OpenBy 按当前配置打开这些文件"

        fallbackApplication.stringValue = handler.fallbackApplication.bundleIdentifier.isEmpty
            ? "尚未设置"
            : handler.fallbackApplication.displayName

        fallbackIcon.image = applicationIcon(handler.fallbackApplication)
        fallbackApplication.toolTip = fallbackApplication.stringValue
        ruleHeight.constant = CGFloat(max(1, min(5, handler.rules.count))) * SettingsRuleCell.rowHeight
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
            feedbackLabel.stringValue = "可添加文件夹规则，为不同文件夹选择应用。"
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
            return ("尚未启用 · 可以先添加文件夹规则", .systemOrange)
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
        alert.messageText = existing == nil ? "添加文件类型" : "编辑类型"
        alert.informativeText = "可添加多个后缀，共用同一套规则。选择预设后仍可修改，例如 jpg, png。"
        alert.addButton(withTitle: existing == nil ? "添加" : "保存")
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "添加示例文件")
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
                let name = inputName.isEmpty ? (extensions.count == 1 ? ".\(extensions[0].uppercased()) 文件" : "自定义类型") : inputName
                let commit = { [weak self] in
                    guard let self else { return }
                    do {
                        let group = try self.model.saveGroup(name: name, extensions: extensions, editing: existing?.id)
                        self.selectedHandlerID = group.id
                        self.reload(message: "已保存“\(name)”（\(extensions.count) 个后缀）。新增格式需启用自动打开。")
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
                                    self.reload(message: "未修改文件类型：部分移除格式无法恢复原应用。请先停用自动打开后重试。", isError: true)
                                case .failure(let error):
                                    self.reload(message: "未修改文件类型：\(error.localizedDescription)", isError: true)
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
                panel.message = "选择示例文件，将它们的后缀加入当前文件类型"
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
        reload(message: "已添加 .\(ext) 文件。下一步可以添加文件夹规则，再启用自动打开。")
        return true
    }

    @objc private func toggleManaged(_ sender: Any?) {
        guard let handler = currentHandler else { return }
        updateManaged(enable: model.managedCount(handler) == 0)
    }

    private func updateManaged(enable: Bool) {
        guard !associationBusy, let handler = currentHandler,
              let type = UTType(handler.contentTypeIdentifier) else { return }

        if !enable {
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
                reload(message: "请先设置“未匹配规则时”使用的应用，再启用自动打开。", isError: true)
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

    @objc private func removeFileType(_ sender: Any?) {
        guard !associationBusy, let handler = currentHandler else { return }
        let ext = typeDisplayName(handler)
        let managed = model.managedCount(handler) > 0

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "移除“\(ext)”？"
        alert.informativeText = managed
            ? "OpenBy 会先恢复原来的默认应用，再删除这里的文件夹规则。"
            : "这会删除该文件类型的所有文件夹规则，不会更改 macOS 当前的默认应用。"
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
        guard !associationBusy, let handler = currentHandler, let window = view.window, editorSession == nil else { return }
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
            self.reload(message: existing == nil ? "文件夹规则已添加。" : "文件夹规则已更新。")
        }
    }

    private func performRuleAction(id: UUID, action: SettingsRuleAction) {
        guard !associationBusy, let handler = currentHandler,
              let row = handler.rules.firstIndex(where: { $0.id == id }) else { return }
        switch action {
        case .edit:
            presentRuleEditor(existing: handler.rules[row])
            return
        case .toggle:
            model.updateRule(handlerID: handler.id, ruleID: id) { $0.enabled.toggle() }
        case .delete:
            ruleTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            deleteRule(nil)
            return
        }
        reload(message: "规则已更新。")
    }

    @objc private func deleteRule(_ sender: Any?) {
        guard let handler = currentHandler else { return }
        let row = ruleTable.selectedRow
        guard row >= 0, row < handler.rules.count else { return }
        let rule = handler.rules[row]

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除这条文件夹规则？"
        alert.informativeText = ruleSummary(rule)
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        model.removeRule(handlerID: handler.id, ruleID: rule.id)
        reload(message: "文件夹规则已删除。")
    }

    @objc private func changeFallback(_ sender: Any?) {
        guard !associationBusy, let handler = currentHandler else { return }
        guard let url = chooseApplication(message: "选择没有匹配到文件夹规则时使用的应用") else { return }
        let reference = SettingsModel.applicationReference(from: url)
        model.updateHandler(id: handler.id) { $0.fallbackApplication = reference }
        reload(message: "已保存应用：\(reference.displayName)。启用自动打开后用于未匹配规则的文件。")
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
        SettingsModel.typeDisplayName(handler)
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

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView === handlerTable ? SettingsTypeRow() : SettingsRuleRow()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === handlerTable {
            guard row < model.configuration.handlers.count else { return nil }
            let handler = model.configuration.handlers[row]
            let identifier = NSUserInterfaceItemIdentifier("handlerCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? SettingsTypeCell ?? SettingsTypeCell()
            cell.identifier = identifier
            cell.name.stringValue = typeDisplayName(handler)
            cell.setStatus(count: handler.displayExtensions.count, managed: model.managedCount(handler), fullyManaged: isManaged(handler))
            cell.icon.image = UTType(handler.contentTypeIdentifier).map { NSWorkspace.shared.icon(for: $0) }
            cell.toolTip = cell.name.stringValue + " · " + cell.subtitle.stringValue
            return cell
        }
        guard let handler = currentHandler, row < handler.rules.count else { return nil }
        let rule = handler.rules[row]
        let identifier = NSUserInterfaceItemIdentifier("ruleCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? SettingsRuleCell ?? SettingsRuleCell()
        cell.identifier = identifier
        cell.folder.stringValue = folderDisplayName(rule.folderPath)
        let folderExists = FileManager.default.fileExists(atPath: PathInput.expandedAbsolutePath(rule.folderPath))
        let appExists = model.resolver.applicationURL(for: rule.targetApplication) != nil
        let issue = !folderExists ? "文件夹不可用" : (!appExists ? "应用不可用" : "")
        cell.path.stringValue = (rule.folderPath as NSString).abbreviatingWithTildeInPath
        cell.path.toolTip = rule.folderPath
        cell.scope.stringValue = (rule.enabled ? "" : "已停用 · ") + (issue.isEmpty ? (rule.includesDescendants ? "包含子文件夹" : "仅当前文件夹") : "⚠ " + issue)
        cell.scope.textColor = issue.isEmpty ? .secondaryLabelColor : .systemOrange
        cell.appName.stringValue = rule.targetApplication.displayName
        cell.appName.toolTip = rule.targetApplication.displayName
        cell.appIcon.image = applicationIcon(rule.targetApplication)
        cell.folder.textColor = rule.enabled ? .labelColor : .secondaryLabelColor
        cell.appName.textColor = rule.enabled ? .labelColor : .secondaryLabelColor
        cell.ruleID = rule.id
        cell.onAction = { [weak self] id, action in self?.performRuleAction(id: id, action: action) }
        cell.ruleEnabled = rule.enabled
        cell.edit.isEnabled = !associationBusy
        cell.more.isEnabled = !associationBusy
        cell.edit.setAccessibilityLabel("第 \(row + 1) 条规则（\(cell.folder.stringValue)）：编辑")
        cell.more.setAccessibilityLabel("第 \(row + 1) 条规则（\(cell.folder.stringValue)）：更多操作")
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
        guard tableView === ruleTable, !associationBusy,
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
        guard !associationBusy else { return [] }
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
        guard !associationBusy, let handler = currentHandler,
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
    private let enabledButton = NSButton(checkboxWithTitle: "启用这条规则", target: nil, action: nil)
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
    private let saveButton = SettingsButton(title: "保存规则", target: nil, action: nil)

    func present(on parent: NSWindow, completion: @escaping (FolderRule?) -> Void) {
        self.completion = completion
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 430), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = existing == nil ? "添加文件夹规则" : "编辑文件夹规则"
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
        let chooseFolder = SettingsButton(title: "选择文件夹", target: self, action: #selector(chooseFolder(_:)))
        SettingsStyle.button(chooseFolder, symbol: "folder")
        let folderRow = SettingsStyle.row([folderField, chooseFolder])
        descendantsButton.state = (existing?.includesDescendants ?? true) ? .on : .off
        descendantsButton.target = self
        descendantsButton.action = #selector(updatePreview(_:))
        applicationLabel.stringValue = targetApplication.bundleIdentifier.isEmpty ? "尚未选择应用" : targetApplication.displayName
        applicationLabel.lineBreakMode = .byTruncatingMiddle
        applicationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let chooseApp = SettingsButton(title: "选择应用", target: self, action: #selector(chooseApplication(_:)))
        SettingsStyle.button(chooseApp, symbol: "app")
        let appRow = SettingsStyle.row([applicationLabel, SettingsStyle.spacer(), chooseApp])
        enabledButton.state = (existing?.enabled ?? true) ? .on : .off
        previewLabel.font = .systemFont(ofSize: 12)
        previewLabel.maximumNumberOfLines = 0
        previewLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        let cancel = SettingsButton(title: "取消", target: self, action: #selector(cancelEditing(_:)))
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
        panel.message = "选择符合这条文件夹规则时使用的应用"
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
        previewLabel.stringValue = "启用自动打开和本规则后，“\(folder)”中的匹配文件使用 \(app) 打开（\(scope)）。"
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
        nameField.placeholderString = "名称（可选），例如：工作图片"
        nameField.stringValue = existing?.groupName ?? ""
        nameField.setAccessibilityLabel("文件类型名称")
        extensionsField.placeholderString = "例如：jpg, png, webp"
        extensionsField.stringValue = existing?.displayExtensions.joined(separator: ", ") ?? ""
        extensionsField.setAccessibilityLabel("组内文件后缀，可增删")
        extensionsField.cell?.wraps = true
        extensionsField.cell?.isScrollable = false
        extensionsField.usesSingleLineMode = false
        let hint = SettingsStyle.label("用逗号或空格分隔；删除后缀即可将它排除。", size: 11, color: .secondaryLabelColor)
        let stack = SettingsStyle.column([
            SettingsStyle.label("预设"), preset,
            SettingsStyle.label("名称"), nameField,
            SettingsStyle.label("文件后缀"), extensionsField, hint,
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
