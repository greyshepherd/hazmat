import SwiftUI

@main
struct HazmatApp: App {
    /// The window's identity, so a command with the window closed can bring it
    /// back before asking it for a name or a confirmation.
    static let windowID = "main"

    @State private var model = ShellModel()

    var body: some Scene {
        WindowGroup("Hazmat", id: Self.windowID) {
            ShellView(model: model)
        }
        .defaultSize(width: 1080, height: 700)
        .windowResizability(.contentMinSize)
        .commands { ShellCommands(model: model) }

        Settings {
            SettingsView(model: model)
        }

        MenuBarExtra {
            StatusMenu(model: model)
        } label: {
            StatusMark(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}
