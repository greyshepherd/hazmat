import SwiftUI

@main
struct HazmatApp: App {
    @NSApplicationDelegateAdaptor(Launch.self) private var launch
    @State private var model: ShellModel

    init() {
        let model = ShellModel(updates: UpdateChecker())
        _model = State(initialValue: model)
        launch.showWindow = { model.showWindow() }
    }

    /// The shell window is the model's, not a scene's: a scene keeps its
    /// window and the view tree under it after a close, and the model lets
    /// both go. The settings scene carries the menu bar's commands.
    var body: some Scene {
        MenuBarExtra {
            StatusMenu(model: model)
        } label: {
            StatusMark(model: model)
        }
        .menuBarExtraStyle(.menu)
        .commands { ShellCommands(model: model) }

        Settings {
            SettingsView(model: model)
        }
    }
}
