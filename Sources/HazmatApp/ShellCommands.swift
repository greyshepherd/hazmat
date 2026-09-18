import HazmatAppSupport
import HazmatCore
import SwiftUI

/// The menu bar: every action the window offers, with its shortcut, built from
/// the commands value in app support and performed by the one shell model.
struct ShellCommands: Commands {
    let model: ShellModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // The application menu's own settings item belongs to the settings scene,
        // which declares it. This group adds the check beside it, before it, the
        // way the platform orders them.
        CommandGroup(before: .appSettings) {
            items("app")
        }
        CommandGroup(replacing: .newItem) {
            items("file")
        }
        CommandGroup(after: .pasteboard) {
            items("edit")
        }
        CommandMenu("Hosts") {
            items("hosts")
        }
        CommandGroup(replacing: .sidebar) {
            items("window")
        }
        CommandGroup(replacing: .help) {
            items("help")
        }
    }

    /// The one value the window and the menu bar both render. Rebuilding it here
    /// would be a second copy that can disagree with the model's, and did: the
    /// update check the model offered never reached the application menu.
    private var presentation: CommandPresentation { model.commands }

    @ViewBuilder
    private func items(_ menu: String) -> some View {
        ForEach(presentation.menu(menu)?.items ?? []) { item in
            Button(item.title) {
                perform(item)
            }
            .keyboardShortcut(item.shortcut.map(shortcut))
            .disabled(!item.isEnabled)
        }
    }

    /// A command that asks the window for something still works with the window
    /// closed: the window comes back first, and the ask follows once it is
    /// there to present it.
    private func perform(_ item: CommandPresentation.Item) {
        guard item.needsTheWindow else {
            model.perform(item.action)
            return
        }
        openWindow(id: HazmatApp.windowID)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            model.perform(item.action)
        }
    }

    private func shortcut(_ shortcut: CommandPresentation.Shortcut) -> KeyboardShortcut {
        KeyboardShortcut(key(shortcut.key), modifiers: modifiers(shortcut.modifiers))
    }

    private func key(_ key: String) -> KeyEquivalent {
        switch key {
        case "delete": return .delete
        case "return": return .return
        default: return KeyEquivalent(Character(key))
        }
    }

    private func modifiers(_ modifiers: CommandPresentation.Modifiers) -> EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }
}
