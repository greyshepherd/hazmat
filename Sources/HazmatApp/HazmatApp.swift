import SwiftUI

@main
struct HazmatApp: App {
    @State private var model = ShellModel(updates: UpdateChecker())

    var body: some Scene {
        WindowGroup("Hazmat") {
            ShellView(model: model)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            StatusMenu(model: model)
        } label: {
            StatusLabel(title: model.menu.statusTitle)
        }
        .menuBarExtraStyle(.menu)
    }
}
