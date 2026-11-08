import AppKit
import SwiftUI

/// A full-width button that opens a menu. SwiftUI's `Menu` doesn't stretch on macOS.
struct PopUpMenuButton: View {
    struct Item {
        let title: String
        let action: () -> Void
        static var divider: Item { Item(title: "", action: {}) }
    }

    let title: String
    let items: [Item]

    var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityHint("Opens a menu")
    }

    private func showMenu() {
        let menu = NSMenu()
        for item in items {
            if item.title.isEmpty {
                menu.addItem(.separator())
            } else {
                menu.addItem(ClosureMenuItem(title: item.title, action: item.action))
            }
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
