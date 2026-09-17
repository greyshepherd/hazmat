import SwiftUI

@main
struct HazmatApp: App {
    @State private var model = ShellModel()

    var body: some Scene {
        WindowGroup("Hazmat") {
            ShellView(model: model)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            StatusMenu(model: model)
        } label: {
            Text(model.menu.statusTitle)
        }
        .menuBarExtraStyle(.menu)
    }
}
