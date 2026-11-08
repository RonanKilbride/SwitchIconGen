import AppKit
import SwiftUI

/// The main window, built on AppKit's split view: sidebar, canvas and a settings inspector.
///
/// The hosting controllers don't size their views (`sizingOptions = []`), so SwiftUI content
/// never feeds minimum sizes back into the split view. Column limits are fixed here instead,
/// which keeps layout stable on every macOS version and screen size.
@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private static let contentMinSize = NSSize(width: 860, height: 600)
    private static let defaultContentSize = NSSize(width: 980, height: 680)

    private let splitController: NSSplitViewController

    init(model: AppModel) {
        func host(_ view: some View) -> NSViewController {
            let controller = NSHostingController(rootView: AnyView(view.environment(model)))
            controller.sizingOptions = []
            return controller
        }

        let sidebar = NSSplitViewItem(sidebarWithViewController: host(SearchResultsView()))
        sidebar.minimumThickness = 210
        sidebar.maximumThickness = 304
        sidebar.canCollapse = true

        let canvas = NSSplitViewItem(viewController: host(EditorView()))
        canvas.minimumThickness = 400
        // The canvas doesn't scroll, so its toolbar needs no separator.
        canvas.titlebarSeparatorStyle = .none

        let inspector = NSSplitViewItem(inspectorWithViewController: host(InspectorView()))
        inspector.minimumThickness = 214
        inspector.maximumThickness = 290
        inspector.canCollapse = true

        splitController = NSSplitViewController()
        splitController.splitViewItems = [sidebar, canvas, inspector]

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SwitchIconGen"
        window.contentViewController = splitController
        window.contentMinSize = Self.contentMinSize
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.defaultContentSize)
        window.center()
        window.setFrameAutosaveName("MainWindow")
        // A saved frame from another screen may no longer fit this one.
        if let screen = window.screen?.visibleFrame, !screen.contains(window.frame) {
            window.setFrame(window.frame.intersection(screen), display: false)
        }

        super.init(window: window)

        // Sidebar and inspector widths are remembered between launches.
        let split = splitController.splitView
        let hasSavedWidths = UserDefaults.standard.object(forKey: "NSSplitView Subview Frames MainSplit") != nil
        split.autosaveName = "MainSplit"
        if !hasSavedWidths {
            split.layoutSubtreeIfNeeded()
            split.setPosition(232, ofDividerAt: 0)
            split.setPosition(split.bounds.width - 236, ofDividerAt: 1)
        }
        let toolbar = NSToolbar(identifier: "Main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        model.undoManager = window.undoManager
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .inspectorTrackingSeparator, .flexibleSpace, .toggleInspector]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        nil // only system items
    }
}
