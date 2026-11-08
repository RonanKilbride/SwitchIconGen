import SwiftUI

/// Exported and applied icons, newest first. Click to reopen; drag out for the PNG.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingClear = false

    private var history: HistoryStore { model.history }
    @State private var selection: HistoryStore.Entry.ID?

    private var reopenSelection: Binding<HistoryStore.Entry.ID?> {
        Binding {
            selection
        } set: { id in
            selection = id
            if let id, let entry = history.entries.first(where: { $0.id == id }) { model.reopen(entry) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(history.entries, selection: reopenSelection) { entry in
                HistoryRow(entry: entry)
                    .tag(entry.id)
                    .contextMenu { menu(for: entry) }
            }
            .overlay {
                if history.entries.isEmpty {
                    ContentUnavailableView {
                        Label("No History Yet", systemImage: "clock")
                    } description: {
                        Text("Icons you export or apply to games appear here.")
                    }
                }
            }

            if !history.entries.isEmpty {
                Divider()
                HStack {
                    Text("\(history.entries.count) \(history.entries.count == 1 ? "item" : "items")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History…") { confirmingClear = true }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        } message: {
            Text("This removes the list and its saved previews. Exported files and icons on your games aren't affected.")
        }
    }

    @ViewBuilder
    private func menu(for entry: HistoryStore.Entry) -> some View {
        let existing = entry.urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        Button("Open in Editor") { model.reopen(entry) }
            .disabled(!entry.canReopen)
        Divider()
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(existing) }
            .disabled(existing.isEmpty)
        if entry.kind == .applied {
            Button("Restore Original Icon…") { model.requestRestore(of: existing) }
                .disabled(existing.isEmpty)
        }
        Divider()
        Button("Remove from History", role: .destructive) { history.remove(entry) }
    }
}

private struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    let entry: HistoryStore.Entry

    var body: some View {
        HStack(spacing: 10) {
            AsyncIconImage(url: model.history.iconURL(for: entry))
                .frame(width: 44, height: 44)
                .onDrag {
                    guard let url = model.history.dragFile(for: entry) else { return NSItemProvider() }
                    return NSItemProvider(contentsOf: url) ?? NSItemProvider()
                }
                .help("Drag to save this icon as a PNG")

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.date, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let names = entry.urls.map { FileManager.default.displayName(atPath: $0.path) }
        switch entry.kind {
        case .exported:
            return "Exported \(entry.format ?? "file") · \(names.first ?? "")"
        case .applied:
            return names.count == 1 ? "Applied to \(names[0])" : "Applied to \(names.count) items"
        }
    }
}

/// Loads a PNG off the main thread.
private struct AsyncIconImage: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary)
            }
        }
        .task(id: url) {
            image = await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
        }
    }
}
