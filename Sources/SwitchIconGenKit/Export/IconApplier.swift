import AppKit

/// Sets or clears custom Finder icons, keeping what was there so changes can be undone.
@MainActor
public enum IconApplier {
    /// A target's icon state before we touched it.
    public struct Backup {
        public let url: URL
        /// The custom icon it had, or `nil` if it showed its built-in icon.
        public let previousCustomIcon: NSImage?
    }

    public struct Outcome {
        public let succeeded: [URL]
        public let failed: [URL]
        /// One per succeeded target, for `undo`.
        public let backups: [Backup]

        public var summary: String {
            let names = { (urls: [URL]) in urls.map(IconApplier.displayName).joined(separator: ", ") }
            switch (succeeded.isEmpty, failed.isEmpty) {
            case (false, true): return "Updated \(names(succeeded))."
            case (true, false): return "Couldn't change \(names(failed)). It may be read-only or need admin rights."
            case (false, false): return "Updated \(names(succeeded)). Couldn't change \(names(failed))."
            case (true, true): return "Nothing selected."
            }
        }
    }

    /// - Parameter icon: the new icon, or `nil` to restore the built-in one.
    public static func apply(_ icon: NSImage?, to urls: [URL]) -> Outcome {
        var succeeded: [URL] = []
        var failed: [URL] = []
        var backups: [Backup] = []
        for url in urls {
            let backup = Backup(url: url, previousCustomIcon: customIcon(of: url))
            if setIcon(icon, on: url) {
                succeeded.append(url)
                backups.append(backup)
            } else {
                failed.append(url)
            }
        }
        return Outcome(succeeded: succeeded, failed: failed, backups: backups)
    }

    /// Puts each target back the way `apply` found it.
    @discardableResult
    public static func undo(_ backups: [Backup]) -> Outcome {
        var succeeded: [URL] = []
        var failed: [URL] = []
        for backup in backups {
            if setIcon(backup.previousCustomIcon, on: backup.url) {
                succeeded.append(backup.url)
            } else {
                failed.append(backup.url)
            }
        }
        return Outcome(succeeded: succeeded, failed: failed, backups: [])
    }

    /// Whether Finder's "has custom icon" bit is set (FinderInfo flag 0x0400, bytes 8–9).
    public nonisolated static func hasCustomIcon(_ url: URL) -> Bool {
        var info = [UInt8](repeating: 0, count: 32)
        let length = getxattr(url.path, "com.apple.FinderInfo", &info, info.count, 0, 0)
        guard length >= 10 else { return false }
        return (UInt16(info[8]) << 8 | UInt16(info[9])) & 0x0400 != 0
    }

    /// The icon Finder currently shows, for confirmation UI.
    public static func currentIcon(of url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    public nonisolated static func displayName(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.path)
    }

    private static func customIcon(of url: URL) -> NSImage? {
        // With the custom-icon bit set, Finder's icon *is* the custom icon.
        hasCustomIcon(url) ? currentIcon(of: url) : nil
    }

    private static func setIcon(_ icon: NSImage?, on url: URL) -> Bool {
        guard NSWorkspace.shared.setIcon(icon, forFile: url.path, options: []) else { return false }
        // Makes Finder redraw now.
        NSWorkspace.shared.noteFileSystemChanged(url.path)
        return true
    }
}
