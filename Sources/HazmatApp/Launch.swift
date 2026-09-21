import AppKit

/// What the application does at launch and on a reopen from the Dock: shows
/// the window, the way the window scene did.
final class Launch: NSObject, NSApplicationDelegate {
    var showWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        showWindow?()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            showWindow?()
        }
        return false
    }
}
