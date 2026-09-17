import SwiftUI

@main
struct HazmatApp: App {
    var body: some Scene {
        WindowGroup("Hazmat") {
            ShellView(model: ShellModel())
        }
        .windowResizability(.contentSize)
    }
}
