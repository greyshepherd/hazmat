import AppKit
import HazmatCore
import SwiftUI
import XCTest

@testable import HazmatApp
@testable import HazmatAppSupport

/// The window is the model's: shown when asked for, one however often it is
/// asked for, and let go of when it closes — the window, its hosting view and
/// everything the view tree built — while what it showed stays on the model.
@MainActor
final class ShellWindowCloseTests: XCTestCase {
    func testShowingTheWindowMakesOneAndShowsTheSameOneAgain() throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let model = world.model(showing: false)
        XCTAssertNil(model.shellWindow)
        XCTAssertFalse(model.isWindowShowing)

        model.showWindow()
        let window = try XCTUnwrap(model.shellWindow)
        defer { window.close() }

        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(model.isWindowShowing)
        XCTAssertEqual(window.title, "Hazmat")
        XCTAssertTrue(window.contentView is NSHostingView<ShellView>)
        // The shell's minimum, plus the title bar the content extends under.
        XCTAssertEqual(window.contentMinSize.width, 880, "the content minimum is the shell's")
        XCTAssertGreaterThanOrEqual(window.contentMinSize.height, 560)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView), "the sidebar extends into the title bar, as the scene's did")

        model.showWindow()
        XCTAssertTrue(model.shellWindow === window, "asked for again, the same window comes forward")
    }

    func testClosingTheWindowReleasesItAndResetsTheResolvedView() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let model = world.model(showing: false)
        model.showWindow()
        model.resolvedViewMode = .table
        weak var window = model.shellWindow
        weak var host = model.shellWindow?.contentView
        XCTAssertNotNil(window)
        XCTAssertNotNil(host)

        model.shellWindow?.close()
        await settle { !model.isWindowShowing }

        XCTAssertFalse(model.isWindowShowing)
        XCTAssertEqual(model.resolvedViewMode, .text)
        XCTAssertNil(model.shellWindow)
        // The close animates the window out and holds it until it is done.
        await settle(within: 5) { window == nil && host == nil }
        XCTAssertNil(host, "the hosting view and the tree under it are released")
        XCTAssertNil(window, "and so is the window")
    }

    func testAnotherWindowClosingLeavesTheShellWindowAlone() throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let model = world.model(showing: false)
        model.showWindow()
        defer { model.shellWindow?.close() }
        model.resolvedViewMode = .table

        let other = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 400, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        other.isReleasedWhenClosed = false
        other.orderFront(nil)
        other.close()

        XCTAssertTrue(model.isWindowShowing)
        XCTAssertNotNil(model.shellWindow)
        XCTAssertEqual(model.resolvedViewMode, .table)
    }

    // MARK: - What a closed window keeps

    /// Closing the window lets the selected profile's composition and every
    /// parse go: the reads that follow carry the rendered block's digest, which
    /// is what the menu compares, and hold no parse and no bytes. Reopening
    /// reads in full again and holds the selected profile's layers parsed.
    func testClosingTheWindowLetsTheParsesGoAndReopeningParsesAgain() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let sessions = Sessions()
        let model = world.model(showing: false) { session, selection, search, activation, detail in
            sessions.record(session)
            let reading = session.editor.reading(selection: selection, search: search, detail: detail)
            return (editor: reading.presentation, reading: activation ? reading.activation : nil)
        }
        model.showWindow()
        model.selection = .profile(world.work)
        model.selectionChanged()
        await settle { model.editor.selectedProfile == world.work && model.editor.resolved.composition != nil }
        let cache = try XCTUnwrap(sessions.last?.cache)
        let layout = try XCTUnwrap(sessions.last?.layout)
        XCTAssertEqual(cache.heldParses, [layout.fragmentURL(world.base), layout.fragmentURL(world.project)])
        XCTAssertTrue(cache.derivationKeys.contains { $0.kind == .block }, "the showing window holds the block's bytes")
        let digest = model.editor.renderedDigest

        model.shellWindow?.close()
        await settle { model.editor.resolved.composition == nil }

        XCTAssertEqual(model.editor.renderedDigest, digest, "the rendered block's digest is kept for the menu")
        XCTAssertNil(model.editor.rendering, "its bytes are not")
        XCTAssertEqual(model.editor.entryCount, 2)
        XCTAssertEqual(model.editor.selectedProfile, world.work)
        XCTAssertTrue(cache.heldParses.isEmpty, "no parse is held for a window that is not showing")
        XCTAssertFalse(cache.derivationKeys.contains { $0.kind == .block }, "and no block's bytes")
        model.refresh()
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(model.editor.resolved.composition, "a read with the window closed composes nothing")
        XCTAssertTrue(cache.heldParses.isEmpty)

        model.showWindow()
        defer { model.shellWindow?.close() }
        await settle { model.editor.resolved.composition != nil }

        XCTAssertEqual(cache.heldParses, [layout.fragmentURL(world.base), layout.fragmentURL(world.project)], "reopening parses the layers again")
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
            let reading = session.editor.reading(selection: selection, search: search, detail: detail)
            return (editor: reading.presentation, reading: activation ? reading.activation : nil)
        }
        XCTAssertNil(model.editor.resolved.composition, "the launch read carries no composition")
        XCTAssertNotNil(model.editor.renderedDigest, "but the digest the menu compares")
        XCTAssertNil(model.editor.rendering, "and not the bytes")
        model.refresh()
        try? await Task.sleep(for: .milliseconds(200))
        let cache = try XCTUnwrap(sessions.last?.cache)
        XCTAssertNil(model.editor.resolved.composition)
        XCTAssertTrue(cache.heldParses.isEmpty, "no parse is held for a window that has not shown")

        model.showWindow()
        defer { model.shellWindow?.close() }
        await settle { model.editor.resolved.composition != nil }

        XCTAssertEqual(cache.heldParses.count, 2, "the showing window's read parses the selected profile's layers")
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
        let model = world.model(showing: false)
        model.showWindow()
        model.selection = .fragment(world.base)
        model.selectionChanged()
        await settle { model.editor.selectedFragment == world.base && model.fragmentDraft == world.baseText }

        model.fragmentDraft = "127.0.0.1\tedited.example\n"
        model.shellWindow?.close()
        await settle { model.editor.fragmentText.isEmpty }

        XCTAssertEqual(model.fragmentDraft, "127.0.0.1\tedited.example\n", "an unsaved edit is kept")
        XCTAssertTrue(model.fragmentIsDirty)

        model.showWindow()
        await settle { !model.editor.fragmentText.isEmpty }
        XCTAssertTrue(model.editor.hasDetail, "the showing window reads in full")
        XCTAssertEqual(model.editor.selectedFragment, world.base, "the same item is selected")
        XCTAssertEqual(model.fragmentDraft, "127.0.0.1\tedited.example\n", "and still there once the window shows")
        XCTAssertTrue(model.fragmentIsDirty)

        model.fragmentDraft = world.baseText
        model.shellWindow?.close()
        await settle { model.editor.fragmentText.isEmpty && model.fragmentDraft.isEmpty }
        XCTAssertFalse(model.fragmentIsDirty, "a clean draft is let go with the text")

        model.showWindow()
        defer { model.shellWindow?.close() }
        await settle { model.fragmentDraft == world.baseText }
        XCTAssertTrue(model.editor.hasDetail)
        XCTAssertEqual(model.fragmentDraft, world.baseText, "the clean draft is read again")
        XCTAssertFalse(model.fragmentIsDirty)
    }
}
