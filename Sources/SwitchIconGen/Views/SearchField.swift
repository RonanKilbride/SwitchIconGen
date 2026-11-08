import AppKit
import SwiftUI

/// An `NSSearchField` bound to a string.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String

    /// Focuses the field, for the Find command.
    @MainActor static func focus() {
        guard let field = current, let window = field.window else { return }
        window.makeFirstResponder(field)
    }

    @MainActor private static weak var current: NSSearchField?

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel(prompt)
        Self.current = field
        return field
    }

    /// Sized by SwiftUI, like `SegmentedTabs`.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSearchField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: 24)
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = prompt
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
