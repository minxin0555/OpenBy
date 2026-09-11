import AppKit
import UniformTypeIdentifiers

// Compile with application sources to inspect internal UI without exposing a public API.
private final class LayoutProvider: DefaultAppProviding {
    var current: [String: String] = [:]
    func currentDefaultApplicationBundleID(toOpen type: UTType) -> String? { current[type.identifier] }
    func currentDefaultApplicationURL(toOpen type: UTType) -> URL? { nil }
    func applicationURL(withBundleIdentifier id: String) -> URL? { nil }
    func setDefaultApplication(_ url: URL, toOpen type: UTType, completion: @escaping (Error?) -> Void) {
        fatalError("Layout checks must never change system associations")
    }
}

try MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenBy-layout-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationStore(fileURL: directory.appendingPathComponent("config.json"))
    let reference = ApplicationReference(bundleIdentifier: "test.reader", displayName: "测试阅读器")
    let handler = FileHandler(contentTypeIdentifier: UTType.jpeg.identifier, fallbackApplication: reference,
                              displayExtensions: ["jpg", "png"], rules: [
                                FolderRule(folderPath: "/tmp", includesDescendants: true, targetApplication: reference)
                              ], groupName: "图片")
    try store.save(Configuration(schemaVersion: ConfigurationMigration.currentVersion, handlers: [handler]))
    let provider = LayoutProvider()
    let model = SettingsModel(store: store,
                              resolver: ApplicationResolver(locator: WorkspaceAppLocator(), ownBundleIdentifier: "test.openby"),
                              associationService: AssociationService(provider: provider),
                              openByBundleID: "test.openby", onConfigurationChanged: nil)
    let controller = SettingsWindowController(model: model)
    controller.show()
    let window = controller.window!
    defer { window.orderOut(nil) }

    @MainActor func checkWidth(_ expected: CGFloat, _ context: String) {
        window.contentView!.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let actual = window.contentView!.bounds.width
        precondition(abs(actual - expected) < 1, "\(context): requested \(expected), actual \(actual)")
        precondition(window.styleMask.contains(.resizable), "Window must remain resizable")
        print("PASS \(context): \(actual) pt")
    }

    // Regression: a full-width stack of buttons with required hugging capped the window at 668 pt.
    checkWidth(1000, "default width after layout")
    @MainActor func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
    let views = descendants(window.contentView!)
    let ruleTable = views.compactMap { $0 as? NSTableView }.first { $0.headerView == nil && $0.rowHeight == 94 }!
    ruleTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    precondition(ruleTable.selectionHighlightStyle == .none, "Rule clicks must not produce selection highlighting")
    let ruleRow = ruleTable.rowView(atRow: 0, makeIfNecessary: true)!
    precondition(ruleRow.interiorBackgroundStyle == .normal, "Rule text must retain readable normal colors")
    let buttons = views.compactMap { $0 as? SettingsButton }
    precondition(!buttons.isEmpty)
    for button in buttons {
        let wasHidden = button.isHidden
        button.isHidden = true
        precondition(!button.isHovered, "Hidden controls cannot be hovered")
        button.isHidden = wasHidden
    }
    window.orderOut(nil)
    precondition(buttons.allSatisfy { !$0.isHovered }, "Closed windows cannot retain button hover")
    controller.show()
    print("PASS rule selection readability and hover visibility")
    let secondHandler = model.addHandler(extension: "txt")!
    controller.focus(handlerID: secondHandler.id)
    precondition(ruleTable.numberOfRows == 0, "Menu navigation must show the target handler's rules")
    let labels = descendants(window.contentView!).compactMap { $0 as? NSTextField }
    precondition(labels.contains { $0.stringValue == "文本文件" && !$0.isHiddenOrHasHiddenAncestor },
                 "Menu navigation must show the target handler's name")
    controller.focus(handlerID: handler.id)
    precondition(ruleTable.numberOfRows == 1, "Switching back must restore the original rules")
    model.removeHandler(id: secondHandler.id)
    controller.reloadFromModel()
    print("PASS direct navigation to file type settings")
    for state in 0...2 {
        provider.current = state == 0 ? [:] : [UTType.jpeg.identifier: "test.openby"]
        if state == 2 { provider.current[UTType.png.identifier] = "test.openby" }
        controller.reloadFromModel()
        for width: CGFloat in [1000, 800, 1440] {
            window.setContentSize(NSSize(width: width, height: 680))
            checkWidth(width, "association state \(state), resize")
        }
    }
    window.setContentSize(NSSize(width: 1000, height: 680))
    window.orderOut(nil)
    controller.show()
    checkWidth(1000, "reopen preserves user width")
    window.setContentSize(NSSize(width: 600, height: 400))
    checkWidth(800, "minimum width")
    precondition(window.frame.height >= 559, "Minimum window height must be respected")
    model.removeHandler(id: handler.id)
    controller.reloadFromModel()
    window.setContentSize(NSSize(width: 1440, height: 680))
    checkWidth(1440, "empty state")
}
