import AppKit
import SwiftUI
import XCTest

@testable import HazmatApp

/// Closing the window is what lets the panes go: a SwiftUI window that closes
/// keeps its view tree, so the model gives the panes a new identity and puts the
/// resolved block back to text, and the table of a hundred thousand rows is
/// released rather than kept for a window nobody is looking at.
@MainActor
final class ShellWindowCloseTests: XCTestCase {
    func testClosingTheShellWindowRetiresThePanesAndResetsTheResolvedView() throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let model = world.model()
        let window = Self.window()
        model.windowChanged(window)
        model.resolvedViewMode = .table
        let generation = model.paneGeneration

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)

        XCTAssertEqual(model.paneGeneration, generation + 1, "the panes are given a new identity")
        XCTAssertEqual(model.resolvedViewMode, .text)
    }

    func testAnotherWindowClosingLeavesThePanesAlone() throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let model = world.model()
        model.windowChanged(Self.window())
        model.resolvedViewMode = .table
        let generation = model.paneGeneration

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: Self.window())

        XCTAssertEqual(model.paneGeneration, generation)
        XCTAssertEqual(model.resolvedViewMode, .table)
    }

    /// The scene builds the panes from the identity, so what the closed window
    /// built is no longer in the view tree once it closes.
    func testTheSceneReplacesThePanesWhenTheWindowCloses() throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let model = world.model()
        let window = Self.window()
        let host = NSHostingView(rootView: ShellView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        model.windowChanged(window)

        let before = Self.allSubviews(of: host).filter { $0 is NSTextView }
        XCTAssertFalse(before.isEmpty, "the fragment's text view is built")

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()

        let after = Self.allSubviews(of: host).filter { $0 is NSTextView }
        for view in after {
            XCTAssertFalse(before.contains { $0 === view }, "the closed window's text view is gone")
        }
    }

    private static func allSubviews(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { allSubviews(of: $0) }
    }

    private static func window() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
    }
}
