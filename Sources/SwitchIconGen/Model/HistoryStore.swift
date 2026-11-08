import AppKit
import ImageIO
import Observation
import SwitchIconGenKit
import UniformTypeIdentifiers

/// Exported and applied icons, saved in ~/Library/Application Support/SwitchIconGen/History.
@MainActor
@Observable
final class HistoryStore {
    struct Entry: Codable, Identifiable, Hashable {
        enum Kind: String, Codable { case exported, applied }

        let id: UUID
        let date: Date
        let kind: Kind
        let title: String
        /// The rendered icon's file name in the history folder.
        let iconFile: String
        /// The exported files, or the items the icon was applied to.
        let paths: [String]
        /// "PNG" or "ICNS" for exports.
        let format: String?
        /// The source art and settings, for reopening. Missing in entries from older versions.
        let artFile: String?
        let options: IconOptions?

        var canReopen: Bool { artFile != nil && options != nil }

        static func == (a: Entry, b: Entry) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }

        var urls: [URL] { paths.map { URL(filePath: $0) } }
    }

    private(set) var entries: [Entry] = []
    private let folder: URL
    private var indexURL: URL { folder.appending(path: "history.json") }

    init(folder: URL? = nil) {
        let base = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "SwitchIconGen/History", directoryHint: .isDirectory)
        self.folder = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func iconURL(for entry: Entry) -> URL { folder.appending(path: entry.iconFile) }

    /// The entry's source art, if saved.
    func art(for entry: Entry) -> CGImage? {
        guard let file = entry.artFile,
              let source = CGImageSourceCreateWithURL(folder.appending(path: file) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func removeFiles(of entry: Entry) {
        try? FileManager.default.removeItem(at: iconURL(for: entry))
        if let art = entry.artFile { try? FileManager.default.removeItem(at: folder.appending(path: art)) }
    }

    /// Records an export or apply. `icon` is the 1024px render.
    func add(
        _ kind: Entry.Kind, title: String, icon: CGImage, art: CGImage?, options: IconOptions,
        urls: [URL], format: String? = nil
    ) {
        let id = UUID()
        let file = "\(id.uuidString).png"
        guard writePNG(icon, to: folder.appending(path: file)) else { return }
        var artFile: String?
        if let art {
            let name = "\(id.uuidString)-art.png"
            if writePNG(art, to: folder.appending(path: name)) { artFile = name }
        }
        let entry = Entry(
            id: id, date: .now, kind: kind, title: title, iconFile: file, paths: urls.map(\.path),
            format: format, artFile: artFile, options: options
        )
        entries.insert(entry, at: 0)
        save()
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        removeFiles(of: entry)
        save()
    }

    func clear() {
        for entry in entries { removeFiles(of: entry) }
        entries = []
        save()
    }

    /// A copy of the icon with a readable name, for dragging out.
    func dragFile(for entry: Entry) -> URL? {
        let dragFolder = FileManager.default.temporaryDirectory.appending(path: "SwitchIconGen Drags", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dragFolder, withIntermediateDirectories: true)
        let safeTitle = entry.title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: " ")
        let url = dragFolder.appending(path: "\(safeTitle).png")
        try? FileManager.default.removeItem(at: url)
        do {
            try FileManager.default.copyItem(at: iconURL(for: entry), to: url)
            return url
        } catch {
            return nil
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
