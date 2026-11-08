import AppKit
import SwiftUI

@main
struct SwitchIconGenApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    private var model: AppModel { appDelegate.model }

    // The window is created by AppKit (see `MainWindowController`); this scene only carries
    // the menu commands.
    var body: some Scene {
        Settings { EmptyView() }
        .commands {
            CommandGroup(replacing: .appSettings) {}
            CommandGroup(replacing: .newItem) {
                Button("Open Image…") { Panels.chooseArt(for: model) }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Apply to Game…") { Panels.chooseTargets(for: model) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(!model.hasArt)
                Button("Restore Original Icon…") { Panels.chooseRestoreTargets(for: model) }
                Divider()
                Button("Export PNG…") { Panels.export(model, as: .png) }
                    .keyboardShortcut("e")
                    .disabled(!model.hasArt)
                Button("Export ICNS…") { Panels.export(model, as: .icns) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!model.hasArt)
            }
            // No help book.
            CommandGroup(replacing: .help) {}
            CommandGroup(after: .textEditing) {
                Button("Find Game") { SearchField.focus() }
                    .keyboardShortcut("f")
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy Icon") { model.copyToPasteboard() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(!model.hasArt)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed for `swift run`, where there's no app bundle.
        NSApp.setActivationPolicy(.regular)
        let controller = MainWindowController(model: model)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
