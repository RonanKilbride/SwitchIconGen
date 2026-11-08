import AppKit
import SwitchIconGenKit

/// Targets waiting for confirmation.
struct PendingChange: Identifiable {
    enum Kind { case apply, restore }
    let id = UUID()
    let kind: Kind
    let targets: [URL]
}

/// One apply or restore on disk, with what's needed to undo and redo it.
@MainActor
final class FileChange {
    let name: String
    /// The icon to set, or `nil` to restore the original.
    let icon: NSImage?
    let targets: [URL]
    /// The targets' icons before the last perform.
    var backups: [IconApplier.Backup] = []

    init(name: String, icon: NSImage?, targets: [URL]) {
        self.name = name
        self.icon = icon
        self.targets = targets
    }
}

/// The message bar over the canvas.
struct Banner: Identifiable {
    enum Style { case info, success, failure }
    let id = UUID()
    let style: Style
    let message: String
    /// Set when the banner offers Undo.
    let change: FileChange?

    init(_ style: Style, _ message: String, change: FileChange? = nil) {
        self.style = style
        self.message = message
        self.change = change
    }

    /// Info banners fade; changes and failures stay until dismissed.
    var dismissesAutomatically: Bool { style == .info }
}
