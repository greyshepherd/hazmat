import AppKit
import HazmatCore
import SwiftUI
import XCTest

@testable import HazmatApp
@testable import HazmatAppSupport

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
    /// built is no longer in the view tree once it closes. The scene tells the
    /// model its window itself, as soon as it is in one — not on a later
    /// update, which a window open since launch may never get before it closes.
    func testTheSceneReplacesThePanesWhenTheWindowCloses() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let model = world.model()
        let window = Self.window()
        let host = NSHostingView(rootView: ShellView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let before = Self.allSubviews(of: host).filter { $0 is NSTextView }
        XCTAssertFalse(before.isEmpty, "the block's text view is built")

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        await settle { model.editor.resolved.composition == nil }
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()

        let after = Self.allSubviews(of: host).filter { $0 is NSTextView }
        XCTAssertTrue(after.isEmpty, "the closed window's text view is gone and no new one is built for it")
    }

    // MARK: - What a closed window keeps

    /// Closing the window lets the selected profile's composition and every
    /// parse go: the reads that follow carry the rendered block, which is what
    /// the menu compares, and hold no parse. Reopening reads in full again and
    /// holds the selected profile's layers parsed.
    func testClosingTheWindowLetsTheParsesGoAndReopeningParsesAgain() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let sessions = Sessions()
        let model = world.model { session, selection, search, activation, detail in
            sessions.record(session)
            return (
                editor: session.editor.read(selection: selection, search: search, detail: detail),
                reading: activation ? session.catalogue.activation(reading: session.liveFile) : nil
            )
        }
        let window = Self.window()
        model.windowChanged(window)
        model.selection = .profile(world.work)
        model.selectionChanged()
        await settle { model.editor.selectedProfile == world.work && model.editor.resolved.composition != nil }
        let cache = try XCTUnwrap(sessions.last?.cache)
        let layout = try XCTUnwrap(sessions.last?.layout)
        XCTAssertEqual(cache.heldParses, [layout.fragmentURL(world.base), layout.fragmentURL(world.project)])
        let rendering = model.editor.rendering

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        await settle { model.editor.resolved.composition == nil }

        XCTAssertEqual(model.editor.rendering, rendering, "the rendered block is kept for the menu")
        XCTAssertEqual(model.editor.entryCount, 2)
        XCTAssertEqual(model.editor.selectedProfile, world.work)
        XCTAssertTrue(cache.heldParses.isEmpty, "no parse is held for a window that is not showing")
        model.refresh()
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(model.editor.resolved.composition, "a read with the window closed composes nothing")
        XCTAssertTrue(cache.heldParses.isEmpty)

        Self.show(window)
        await settle { model.editor.resolved.composition != nil }

        XCTAssertEqual(cache.heldParses, [layout.fragmentURL(world.base), layout.fragmentURL(world.project)], "reopening parses the layers again")
        window.orderOut(nil)
    }

    /// An application that launches into the menu bar holds nothing of a large
    /// fragment until its window shows: the launch read carries no detail, and
    /// the first read in full is the one the showing window asks for.
    func testNothingIsParsedUntilTheWindowShows() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let sessions = Sessions()
        let model = world.model(showing: false) { session, selection, search, activation, detail in
            sessions.record(session)
            return (
                editor: session.editor.read(selection: selection, search: search, detail: detail),
                reading: activation ? session.catalogue.activation(reading: session.liveFile) : nil
            )
        }
        XCTAssertNil(model.editor.resolved.composition, "the launch read carries no composition")
        XCTAssertNotNil(model.editor.rendering, "but the block the menu compares")
        model.refresh()
        try? await Task.sleep(for: .milliseconds(200))
        let cache = try XCTUnwrap(sessions.last?.cache)
        XCTAssertNil(model.editor.resolved.composition)
        XCTAssertTrue(cache.heldParses.isEmpty, "no parse is held for a window that has not shown")

        let window = Self.window()
        window.orderFront(nil)
        model.windowChanged(window)
        await settle { model.editor.resolved.composition != nil }

        XCTAssertEqual(cache.heldParses.count, 2, "the showing window's read parses the selected profile's layers")
        window.orderOut(nil)
    }

    private final class Sessions: @unchecked Sendable {
        private let lock = NSLock()
        private var sessions: [StoreSession] = []
        var last: StoreSession? { lock.withLock { sessions.last } }
        func record(_ session: StoreSession) { lock.withLock { sessions.append(session) } }
    }

    func testAnEditedDraftSurvivesTheWindowClosingAndACleanOneIsReadAgain() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let model = world.model()
        let window = Self.window()
        model.windowChanged(window)
        model.selection = .fragment(world.base)
        model.selectionChanged()
        await settle { model.editor.selectedFragment == world.base && model.fragmentDraft == world.baseText }

        model.fragmentDraft = "127.0.0.1\tedited.example\n"
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        await settle { model.editor.fragmentText.isEmpty }

        XCTAssertEqual(model.fragmentDraft, "127.0.0.1\tedited.example\n", "an unsaved edit is kept")
        XCTAssertTrue(model.fragmentIsDirty)

        Self.show(window)
        await settle { !model.editor.fragmentText.isEmpty }
        XCTAssertTrue(model.editor.hasDetail, "the showing window reads in full")
        XCTAssertEqual(model.fragmentDraft, "127.0.0.1\tedited.example\n", "and still there once the window shows")
        XCTAssertTrue(model.fragmentIsDirty)

        model.fragmentDraft = world.baseText
        window.orderOut(nil)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        await settle { model.editor.fragmentText.isEmpty && model.fragmentDraft.isEmpty }
        XCTAssertFalse(model.fragmentIsDirty, "a clean draft is let go with the text")

        Self.show(window)
        await settle { model.fragmentDraft == world.baseText }
        XCTAssertTrue(model.editor.hasDetail)
        XCTAssertEqual(model.fragmentDraft, world.baseText, "the clean draft is read again")
        XCTAssertFalse(model.fragmentIsDirty)
        window.orderOut(nil)
    }

    private static func allSubviews(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { allSubviews(of: $0) }
    }

    /// A window off screen, so a test that orders it front shows nothing.
    private static func window() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
    }

    /// What showing a window is to the model: it is on screen and updates. The
    /// window need not become key — one opened from the menu bar is on screen
    /// without the application active.
    private static func show(_ window: NSWindow) {
        window.orderFront(nil)
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
    }
}
