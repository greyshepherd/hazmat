import Foundation
import HazmatAppSupport
import HazmatCore
import XCTest
@testable import HazmatApp

/// The window's reads run away from the main actor and land by ticket: the
/// window keeps what it was showing, a slow read cannot replace a later one, and
/// a read never overwrites a draft the user is editing.
final class ShellModelReadTests: XCTestCase {
    @MainActor
    func testASlowReadDoesNotLandOnTopOfALaterOne() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let counter = ReadCounter()

        let model = world.model { session, selection, search, activation in
            counter.bump()
            if selection == .fragment(world.base) {
                try? await Task.sleep(for: .milliseconds(150))
            }
            return (
                editor: session.editor.read(selection: selection, search: search),
                reading: activation ? session.catalogue.activation(reading: session.liveFile) : nil
            )
        }

        model.selection = .fragment(world.base)
        model.selectionChanged()
        await settle { counter.count >= 1 }

        model.selection = .fragment(world.project)
        model.selectionChanged()
        await settle { model.editor.selectedFragment == world.project }

        // The slow read lands now, well after the later one, and is dropped.
        try? await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(model.editor.selectedFragment, world.project, "the later read's presentation stands")
        XCTAssertEqual(model.editor.fragmentText, "10.0.0.9\talpha.example\n")
        XCTAssertEqual(model.selection, .fragment(world.project))
    }

    @MainActor
    func testAReadLandingOverADirtyDraftKeepsTheDraft() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let counter = ReadCounter()

        let model = world.model { session, selection, search, activation in
            counter.bump()
            try? await Task.sleep(for: .milliseconds(20))
            return (
                editor: session.editor.read(selection: selection, search: search),
                reading: activation ? session.catalogue.activation(reading: session.liveFile) : nil
            )
        }

        model.selection = .fragment(world.base)
        model.selectionChanged()
        await settle { model.editor.selection == .fragment(world.base) }
        XCTAssertEqual(model.fragmentDraft, world.baseText)
        XCTAssertFalse(model.fragmentIsDirty)

        model.fragmentDraft = "127.0.0.1\tedited.example\n"
        XCTAssertTrue(model.fragmentIsDirty)

        model.selectionChanged()
        await settle { counter.count >= 2 }
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(model.fragmentDraft, "127.0.0.1\tedited.example\n", "a read must not overwrite a draft")
        XCTAssertTrue(model.fragmentIsDirty, "the draft still reads as unsaved")
    }

    @MainActor
    func testTheWindowKeepsItsSelectionWhileAReadIsOut() async throws {
        let world = try ShellWorld()
        defer { world.remove() }

        let model = world.model { session, selection, search, activation in
            try? await Task.sleep(for: .milliseconds(60))
            return (
                editor: session.editor.read(selection: selection, search: search),
                reading: nil
            )
        }

        model.selection = .fragment(world.project)
        model.selectionChanged()

        // Nothing waited for the read: the selection is the one just made, and
        // the presentation the window already had is still what it shows.
        XCTAssertEqual(model.selection, .fragment(world.project))
        XCTAssertEqual(model.editor.fragments, [world.base, world.project])

        await settle { model.editor.selection == .fragment(world.project) }
        XCTAssertEqual(model.editor.fragmentText, "10.0.0.9\talpha.example\n")
    }

    /// A write clears `busy` and reports before the read it asks for has landed:
    /// the notice is what the write did, and the window is free while the store
    /// is read again.
    @MainActor
    func testAWriteReportsBeforeTheReadItAsksForLands() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let counter = ReadCounter()
        let gate = Gate()

        let model = world.model { session, selection, search, activation in
            counter.bump()
            await gate.wait()
            return (
                editor: session.editor.read(selection: selection, search: search),
                reading: activation ? session.catalogue.activation(reading: session.liveFile) : nil
            )
        }

        model.createProfile(named: "fresh")
        await settle { counter.count >= 1 }

        XCTAssertFalse(model.busy, "a read does not hold the window")
        XCTAssertEqual(model.notice, .success("the store holds the edit"))
        XCTAssertEqual(model.editor.profiles, [world.work], "the window shows what it had until the read lands")

        await gate.open()
        await settle { model.editor.profiles.count == 2 }

        XCTAssertEqual(model.editor.profiles.map(\.rawValue), ["fresh", "work"])
    }
}
