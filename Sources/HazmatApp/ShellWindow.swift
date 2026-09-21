import AppKit
import SwiftUI

/// The window the shell is shown in: made when it is asked for, one however
/// often it is asked for, and let go of when it closes. A SwiftUI window scene
/// keeps its window and the view tree under it after the window is ordered
/// out; a window the application owns is a window it can free, and freeing it
/// is what releases the hosting view, the text views and the table of a large
/// block, and the layers and surfaces the window drew with.
@MainActor
final class ShellWindow {
    /// The size the window opens at when no frame was saved for it.
    static let defaultSize = NSSize(width: 1080, height: 700)
    /// The name the window's frame is saved under, so its size and position
    /// survive a relaunch.
    static let frameAutosaveName = "ShellWindow"

    private(set) var window: NSWindow?
    /// Set on the main actor and read in `deinit`, which the actor isolation
    /// cannot see into.
    private nonisolated(unsafe) var closeObserver: (any NSObjectProtocol)?
    /// Told when the window has closed and been let go of.
    var onClose: (() -> Void)?

    deinit {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
    }

    /// The window, made around `content` if there is none, brought forward and
    /// made key.
    @discardableResult
    func show<Content: View>(_ content: () -> Content) -> NSWindow {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Hazmat"
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unified
        // Released by letting go of it below, not by the close.
        window.isReleasedWhenClosed = false

        let host = NSHostingView(rootView: content())
        // The content's minimum is the window's, and the title, the toolbar
        // and the sidebar search the content declares reach the window.
        host.sizingOptions = [.minSize]
        host.sceneBridgingOptions = [.title, .toolbars]
        window.contentView = host

        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowClosed() }
        }
        self.window = window
        window.makeKeyAndOrderFront(nil)
        return window
    }

    var isShowing: Bool { window?.isVisible ?? false }

    /// Lets the window go: nothing here refers to it once the close is over,
    /// so the window, its hosting view and the tree under it are freed as
    /// soon as the close itself — which animates the window out — is done
    /// with them.
    private func windowClosed() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        window = nil
        onClose?()
    }
}
