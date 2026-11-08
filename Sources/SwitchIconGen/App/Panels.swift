import AppKit
import UniformTypeIdentifiers

/// Open and save panels, kept out of the model.
@MainActor
enum Panels {
    static func chooseArt(for model: AppModel) {
        let panel = NSOpenPanel()
        panel.message = "Choose artwork to put in the case"
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importArt(from: url)
    }

    static func chooseTargets(for model: AppModel) {
        guard let urls = chooseFiles(
            message: "Choose the games to give this icon",
            prompt: "Choose"
        ) else { return }
        model.requestApply(to: urls)
    }

    static func chooseRestoreTargets(for model: AppModel) {
        guard let urls = chooseFiles(
            message: "Choose the games to restore to their original icon",
            prompt: "Choose"
        ) else { return }
        model.requestRestore(of: urls)
    }

    static func export(_ model: AppModel, as type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = model.suggestedFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.export(as: type, to: url)
    }

    private static func chooseFiles(message: String, prompt: String) -> [URL]? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = prompt
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(filePath: "/Applications")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return nil }
        return panel.urls
    }
}
