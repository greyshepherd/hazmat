import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

/// Each phase comes from a fixture that satisfies only that phase.
final class WindowPhaseTests: XCTestCase {
    private let base = FragmentID("base")
    private let work = ProfileID("work")
    private let other = ProfileID("other")

    private func fixture(layers: String = "base\n", profiles: [(String, String)] = []) throws -> StoreFixture {
        var files: [(String, String)] = [
            ("127.0.0.1\tlocalhost\n", "fragments/base.hosts"),
            (layers, "profiles/work.profile")
        ]
        files.append(contentsOf: profiles)
        return try StoreFixture(store: files, live: "127.0.0.1\tlocalhost\n")
    }

    private func phase(_ fixture: StoreFixture, helper: HelperState = .enabled, selection: SidebarSelection? = .profile(ProfileID("work"))) -> WindowPhase {
        WindowPhase(editor: fixture.model(writer: UnregisteredHelper()).read(selection: selection), helper: helper)
    }

    func testNoStore() throws {
        let store = try TemporaryStore()
        let root = store.root
        store.remove()
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let model = EditorModel(storeRoot: root, fileURL: live.url, writer: UnregisteredHelper())

        let editor = model.read()

        XCTAssertEqual(WindowPhase(editor: editor, helper: .enabled), .noStore)
        XCTAssertEqual(editor.writeState(helper: .enabled).remedy, .createStore)
    }

    func testStoreWithoutProfiles() throws {
        let store = try TemporaryStore()
        defer { store.remove() }
        try store.write("127.0.0.1\tlocalhost\n", to: "fragments/base.hosts")
        try FileManager.default.createDirectory(at: store.root.appendingPathComponent("profiles"), withIntermediateDirectories: true)
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let model = EditorModel(storeRoot: store.root, fileURL: live.url, writer: UnregisteredHelper())

        XCTAssertEqual(WindowPhase(editor: model.read(), helper: .enabled), .noProfiles)
    }

    func testAProfileWithNoLayers() throws {
        let fixture = try fixture(layers: "")
        defer { fixture.remove() }

        let editor = fixture.model(writer: UnregisteredHelper()).read(selection: .profile(work))
        XCTAssertTrue(editor.layers.isEmpty)
        XCTAssertEqual(WindowPhase(editor: editor, helper: .enabled), .profileWithoutLayers)
    }

    func testChangesPending() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        XCTAssertEqual(phase(fixture), .changesPending)
    }

    func testInSync() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        try fixture.applyToLive(work)

        XCTAssertEqual(phase(fixture), .inSync)
    }

    func testBlocked() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        XCTAssertEqual(phase(fixture, helper: .notRegistered), .blocked)
    }

    func testNothingSelectedWhenASearchHidesTheSelection() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let editor = model.read(selection: .profile(work), search: StoreSearch(text: "nothing matches this"))

        XCTAssertNil(editor.selection)
        XCTAssertEqual(WindowPhase(editor: editor, helper: .enabled), .nothingSelected)
    }

    // MARK: - The one prominent action per phase

    func testEveryPhaseOffersAtMostOneProminentAction() throws {
        func action(_ editor: EditorPresentation, _ helper: HelperState) -> WindowAction? {
            let phase = WindowPhase(editor: editor, helper: helper)
            return phase.primaryAction(write: editor.writeState(helper: helper), helper: helper)
        }

        // No store.
        let store = try TemporaryStore()
        let missingRoot = store.root
        store.remove()
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let missing = EditorModel(storeRoot: missingRoot, fileURL: live.url, writer: UnregisteredHelper()).read()
        XCTAssertEqual(WindowPhase(editor: missing, helper: .enabled), .noStore)
        XCTAssertEqual(action(missing, .enabled), .createStore)

        // A store that holds no profiles.
        let emptyStore = try TemporaryStore()
        defer { emptyStore.remove() }
        try FileManager.default.createDirectory(
            at: emptyStore.root.appendingPathComponent("profiles"),
            withIntermediateDirectories: true
        )
        let empty = EditorModel(storeRoot: emptyStore.root, fileURL: live.url, writer: UnregisteredHelper()).read()
        XCTAssertEqual(WindowPhase(editor: empty, helper: .enabled), .noProfiles)
        XCTAssertEqual(action(empty, .enabled), .newProfile)

        // The phases a built store produces, each with its own helper state.
        let layered = try fixture()
        defer { layered.remove() }
        let model = layered.model(writer: UnregisteredHelper())
        let pending = model.read(selection: .profile(work))
        XCTAssertEqual(WindowPhase(editor: pending, helper: .enabled), .changesPending)
        XCTAssertEqual(action(pending, .enabled), .apply)
        XCTAssertEqual(WindowPhase(editor: pending, helper: .notRegistered), .blocked)
        XCTAssertEqual(action(pending, .notRegistered), .installHelper)

        try layered.applyToLive(work)
        let synced = model.read(selection: .profile(work))
        XCTAssertEqual(WindowPhase(editor: synced, helper: .enabled), .inSync)
        XCTAssertEqual(action(synced, .enabled), nil, "an in-sync profile has nothing to promote")

        let layering = try fixture(layers: "")
        defer { layering.remove() }
        let withoutLayers = layering.model(writer: UnregisteredHelper()).read(selection: .profile(work))
        XCTAssertEqual(WindowPhase(editor: withoutLayers, helper: .enabled), .profileWithoutLayers)
        XCTAssertEqual(action(withoutLayers, .enabled), .addFragment)

        let hidden = model.read(selection: .profile(work), search: StoreSearch(text: "nothing matches this"))
        XCTAssertEqual(WindowPhase(editor: hidden, helper: .enabled), .nothingSelected)
        XCTAssertEqual(action(hidden, .enabled), nil)
    }

    func testEveryPhaseSaysWhatItMeans() {
        let phases: [WindowPhase] = [
            .noStore, .noProfiles, .profileWithoutLayers,
            .changesPending, .inSync, .blocked, .nothingSelected
        ]

        XCTAssertEqual(Set(phases.map(\.title)).count, phases.count)
        XCTAssertEqual(Set(phases.map(\.explanation)).count, phases.count)
        for phase in phases {
            XCTAssertFalse(phase.title.isEmpty)
            XCTAssertFalse(phase.explanation.isEmpty)
        }
    }
}
