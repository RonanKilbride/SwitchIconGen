import AppKit
import Observation
import SwitchIconGenKit
import UniformTypeIdentifiers

/// The window's state: search, the icon being edited, and changes made to files.
@MainActor
@Observable
final class AppModel {
    enum SearchState: Equatable {
        case idle
        case searching
        case loaded
        case failed(String)
    }

    // MARK: Search

    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    private(set) var results: [GameArtwork] = []
    private(set) var searchState: SearchState = .idle

    var selectionID: GameArtwork.ID? {
        didSet { if selectionID != oldValue, let game = selectedGame { loadArt(for: game) } }
    }
    var selectedGame: GameArtwork? { results.first { $0.id == selectionID } }

    // MARK: Icon

    /// What the art came from, used for default file names and the header.
    private(set) var artTitle: String?
    private(set) var art: CGImage?
    private(set) var isLoadingArt = false
    var options = IconOptions() {
        didSet {
            guard options != oldValue else { return }
            scheduleRender()
            // Continuous edits (drags, slider) register one step when they end.
            if editStart == nil && !isReplacingArt {
                registerEditUndo(from: oldValue, to: options)
            }
        }
    }
    private(set) var preview: CGImage?
    /// Small sizes rendered natively at 2x, keyed by point size.
    private(set) var sizePreviews: [Int: CGImage] = [:]
    nonisolated static let sizePreviewPoints = [128, 64, 32, 16]
    var banner: Banner?
    /// Items given an icon this session that still have it, newest first.
    private(set) var appliedTargets: [URL] = []

    /// Awaiting confirmation in a sheet.
    var pendingChange: PendingChange?

    var hasArt: Bool { art != nil }
    var suggestedFileName: String { artTitle.map(Self.sanitizedFileName) ?? "Game Icon" }

    // MARK: Dependencies

    let imageLoader: ImageLoader
    let history = HistoryStore()
    private let provider: any ArtworkProvider
    private let composer: IconComposer
    private let exporter: IconExporter

    private var searchTask: Task<Void, Never>?
    private var artTask: Task<Void, Never>?
    private var isRendering = false
    private var needsRender = false
    /// While dragging or pinching, only the preview is rendered.
    private var isAdjustingCrop = false

    init(
        provider: any ArtworkProvider = EShopProvider(),
        imageLoader: ImageLoader = .shared,
        composer: IconComposer = IconComposer()
    ) {
        self.provider = provider
        self.imageLoader = imageLoader
        self.composer = composer
        self.exporter = IconExporter(composer: composer)
        scheduleRender()
    }

    // MARK: - Search

    func retrySearch() {
        scheduleSearch()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            searchState = .idle
            return
        }
        searchState = .searching
        searchTask = Task { [provider] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let found = try await provider.search(query, limit: 40)
                guard !Task.isCancelled else { return }
                results = found
                searchState = .loaded
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                searchState = .failed(error.localizedDescription)
            }
        }
    }

    private func loadArt(for game: GameArtwork) {
        artTask?.cancel()
        isLoadingArt = true
        artTask = Task { [imageLoader] in
            defer { if !Task.isCancelled { isLoadingArt = false } }
            do {
                let image = try await imageLoader.image(at: game.imageURL)
                guard !Task.isCancelled else { return }
                setArt(image, title: game.title, style: CaseStyle(platform: game.primaryPlatform))
            } catch {
                guard !Task.isCancelled else { return }
                banner = Banner(.failure, "Couldn't load art for \(game.title): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Local art

    func importArt(from url: URL) {
        artTask?.cancel()
        isLoadingArt = false
        do {
            let image = try ImageLoader.decode(try Data(contentsOf: url))
            selectionID = nil
            setArt(image, title: url.deletingPathExtension().lastPathComponent)
        } catch {
            banner = Banner(.failure, "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func setArt(_ image: CGImage, title: String, style: CaseStyle? = nil) {
        isReplacingArt = true
        defer { isReplacingArt = false }
        art = image
        artTitle = title
        if let style { options.style = style }
        options.crop = CropSettings()
        // Edits to the previous art don't apply to this one. File changes have their own
        // undo target and are kept.
        undoManager?.removeAllActions(withTarget: self)
        scheduleRender()
    }

    // MARK: - Crop

    /// How far the art can move from centre, in design units.
    var panRange: CGSize {
        guard let art else { return .zero }
        return CaseLayout.panRange(
            artSize: CGSize(width: art.width, height: art.height),
            crop: options.crop,
            showsBand: options.style.showsBand
        )
    }

    func resetCrop() {
        options.crop = CropSettings()
    }

    // MARK: - Rendering

    /// Runs one render at a time, then renders the latest state if it changed meanwhile.
    /// Drags update faster than frames render, so this keeps the preview from lagging.
    private func scheduleRender() {
        needsRender = true
        guard !isRendering else { return }
        isRendering = true
        Task { await renderLatest() }
    }

    private func renderLatest() async {
        while needsRender {
            needsRender = false
            let art = art, options = options, composer = composer
            let includeSizes = !isAdjustingCrop
            let (image, small) = await Task.detached(priority: .userInitiated) {
                let image = try? composer.render(art: art, options: options, pixels: 1024)
                var small: [Int: CGImage]?
                if includeSizes {
                    var sizes: [Int: CGImage] = [:]
                    for points in Self.sizePreviewPoints {
                        sizes[points] = try? composer.render(art: art, options: options, pixels: points * 2)
                    }
                    small = sizes
                }
                return (image, small)
            }.value
            preview = image
            if let small { sizePreviews = small }
        }
        isRendering = false
    }

    /// Brackets a drag or pinch on the art.
    func setAdjustingCrop(_ adjusting: Bool) {
        guard adjusting != isAdjustingCrop else { return }
        isAdjustingCrop = adjusting
        if adjusting {
            beginContinuousEdit()
        } else {
            endContinuousEdit()
            scheduleRender()
        }
    }

    // MARK: - Undo
    //
    // A drag or slider movement registers as one step.

    weak var undoManager: UndoManager?
    private var editStart: IconOptions?
    private var isReplacingArt = false

    func beginContinuousEdit() {
        if editStart == nil { editStart = options }
    }

    func endContinuousEdit() {
        guard let start = editStart else { return }
        editStart = nil
        if start != options { registerEditUndo(from: start, to: options) }
    }

    private func registerEditUndo(from old: IconOptions, to new: IconOptions) {
        guard let undoManager else { return }
        // Setting `options` back registers the inverse, which becomes the redo.
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.options = old }
        }
        undoManager.setActionName(Self.actionName(from: old, to: new))
    }

    static func actionName(from old: IconOptions, to new: IconOptions) -> String {
        if old.style != new.style { return "Change Top Strip" }
        if old.showsSpine != new.showsSpine { return "Side Spine" }
        if new.crop == CropSettings() { return "Reset Position" }
        if old.crop.offset == new.crop.offset { return "Zoom" }
        return "Move Artwork"
    }

    // MARK: - Applying icons
    //
    // Every change to files is confirmed first and can be undone.

    func requestApply(to urls: [URL]) {
        guard hasArt, !urls.isEmpty else { return }
        pendingChange = PendingChange(kind: .apply, targets: urls)
    }

    func requestRestore(of urls: [URL]) {
        guard !urls.isEmpty else { return }
        pendingChange = PendingChange(kind: .restore, targets: urls)
    }

    func confirmPendingChange() {
        guard let change = pendingChange else { return }
        pendingChange = nil

        let icon: NSImage?
        switch change.kind {
        case .apply:
            do {
                icon = try exporter.makeNSImage(art: art, options: options)
            } catch {
                banner = Banner(.failure, "Couldn't render the icon: \(error.localizedDescription)")
                return
            }
        case .restore:
            icon = nil
        }

        let fileChange = FileChange(
            name: change.kind == .apply ? "Apply Icon" : "Restore Original Icon",
            icon: icon,
            targets: change.targets
        )
        perform(fileChange, recordingHistory: true)
    }

    /// Applies a change (or re-applies it on redo) and registers its undo.
    private func perform(_ change: FileChange, recordingHistory: Bool = false) {
        let outcome = IconApplier.apply(change.icon, to: change.targets)
        change.backups = outcome.backups
        trackAppliedTargets(outcome.succeeded)
        if recordingHistory, change.icon != nil, !outcome.succeeded.isEmpty {
            recordHistory(.applied, urls: outcome.succeeded)
        }
        let message = change.icon == nil && outcome.failed.isEmpty
            ? "Restored the original icon of \(outcome.succeeded.map(IconApplier.displayName).joined(separator: ", "))."
            : outcome.summary
        banner = Banner(outcome.failed.isEmpty ? .success : .failure, message, change: outcome.backups.isEmpty ? nil : change)
        guard !outcome.backups.isEmpty, let undoManager else { return }
        undoManager.registerUndo(withTarget: change) { [weak self] change in
            MainActor.assumeIsolated { self?.revert(change, registeringRedo: true) }
        }
        undoManager.setActionName(change.name)
    }

    /// Puts the targets back as they were before `change`.
    private func revert(_ change: FileChange, registeringRedo: Bool) {
        let outcome = IconApplier.undo(change.backups)
        trackAppliedTargets(outcome.succeeded)
        banner = outcome.failed.isEmpty
            ? Banner(.info, "Undone. \(outcome.succeeded.map(IconApplier.displayName).joined(separator: ", ")) is back to how it was.")
            : Banner(.failure, "Couldn't undo the change to \(outcome.failed.map(IconApplier.displayName).joined(separator: ", ")).")
        guard registeringRedo, let undoManager else { return }
        undoManager.registerUndo(withTarget: change) { [weak self] change in
            MainActor.assumeIsolated { self?.perform(change) }
        }
        undoManager.setActionName(change.name)
    }

    /// Restores the apps this session changed.
    func requestRestoreApplied() {
        requestRestore(of: appliedTargets)
    }

    /// Syncs `appliedTargets` with what's on disk.
    private func trackAppliedTargets(_ urls: [URL]) {
        for url in urls {
            appliedTargets.removeAll { $0 == url }
            if IconApplier.hasCustomIcon(url) {
                appliedTargets.insert(url, at: 0)
            }
        }
    }

    /// The banner's Undo button. Also removes the matching ⌘Z step.
    func undo(_ banner: Banner) {
        guard let change = banner.change else { return }
        undoManager?.removeAllActions(withTarget: change)
        revert(change, registeringRedo: false)
    }

    func export(as type: UTType, to url: URL) {
        do {
            if type == .icns {
                try exporter.writeICNS(art: art, options: options, to: url)
            } else {
                try exporter.writePNG(art: art, options: options, to: url)
            }
            banner = Banner(.info, "Saved \(url.lastPathComponent).")
            recordHistory(.exported, urls: [url], format: type == .icns ? "ICNS" : "PNG")
        } catch {
            banner = Banner(.failure, "Export failed: \(error.localizedDescription)")
        }
    }

    private func recordHistory(_ kind: HistoryStore.Entry.Kind, urls: [URL], format: String? = nil) {
        guard let icon = try? composer.render(art: art, options: options, pixels: 1024) else { return }
        history.add(
            kind, title: artTitle ?? "Custom Icon", icon: icon, art: art, options: options,
            urls: urls, format: format
        )
    }

    /// Loads a history entry back into the editor with its art and settings.
    func reopen(_ entry: HistoryStore.Entry) {
        guard let saved = entry.options, let image = history.art(for: entry) else {
            banner = Banner(.info, "This item was saved by an earlier version, so its settings can't be reopened.")
            return
        }
        artTask?.cancel()
        isLoadingArt = false
        selectionID = nil
        setArt(image, title: entry.title)
        isReplacingArt = true
        options = saved
        isReplacingArt = false
    }

    /// Writes a PNG at `pixels` square to a temporary folder, for dragging out.
    func dragFile(pixels: Int) -> URL? {
        guard hasArt else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "SwitchIconGen Drags", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(suggestedFileName) \(pixels)px.png")
        do {
            try exporter.writePNG(art: art, options: options, to: url, pixels: pixels)
            return url
        } catch {
            banner = Banner(.failure, "Couldn't create the file: \(error.localizedDescription)")
            return nil
        }
    }

    func copyToPasteboard() {
        guard let icon = try? exporter.makeNSImage(art: art, options: options) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([icon])
        banner = Banner(.info, "Copied. Paste onto an icon in Finder's Get Info window.")
    }

    /// Images dropped on the preview become the art; anything else gets the icon.
    func handleDrop(_ urls: [URL]) {
        let images = urls.filter { (try? $0.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true }
        if let image = images.first {
            importArt(from: image)
        }
        let targets = urls.filter { !images.contains($0) }
        if !targets.isEmpty {
            if hasArt {
                requestApply(to: targets)
            } else {
                banner = Banner(.info, "Pick a game first, then drop it here to apply.")
            }
        }
    }

    static func sanitizedFileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: " ")
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}
