import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

/// A store whose profile stacks the given fragments, and a live file that holds
/// what the test asks it to.
final class WriteStateTests: XCTestCase {
    private let base = FragmentID("base")
    private let project = FragmentID("project")
    private let work = ProfileID("work")
    private let other = ProfileID("other")

    private func fixture(layers: String = "base\n") throws -> StoreFixture {
        try StoreFixture(
            store: [
                ("127.0.0.1\tlocalhost\n", "fragments/base.hosts"),
                ("10.0.0.9\talpha.example\n", "fragments/project.hosts"),
                (layers, "profiles/work.profile"),
                ("base\nproject\n", "profiles/other.profile")
            ],
            live: "127.0.0.1\tlocalhost\n"
        )
    }

    private func writeState(_ fixture: StoreFixture, helper: HelperState, profile: ProfileID? = nil) -> WriteState {
        let model = fixture.model(writer: UnregisteredHelper())
        return model.read(selection: .profile(profile ?? work)).writeState(helper: helper)
    }

    // MARK: - The live block's state

    func testAnAppliedBlockIsInSync() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        try fixture.applyToLive(work)

        XCTAssertEqual(writeState(fixture, helper: .enabled), .inSync)
    }

    func testADriftedBlockIsPendingWithTheEntryCountItWouldWrite() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        // The live block belongs to another profile, so the selected one is not
        // applied even though the file holds a well-formed block.
        try fixture.applyToLive(other)

        let state = writeState(fixture, helper: .enabled)

        XCTAssertEqual(state, .pending(entries: 1))
        XCTAssertEqual(state.entryCount, 1)
        XCTAssertTrue(state.isPending)
    }

    func testAnAbsentBlockIsPendingRatherThanInSync() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        let state = writeState(fixture, helper: .enabled)

        XCTAssertEqual(state, .pending(entries: 1), "a file that holds no block is not in sync")
    }

    func testTheEntryCountCountsTheLinesTheBlockWouldHold() throws {
        let fixture = try fixture(layers: "base\nproject\n")
        defer { fixture.remove() }

        XCTAssertEqual(writeState(fixture, helper: .enabled), .pending(entries: 2))

        // A later layer overrides the name the earlier one supplied, so the
        // block holds one line rather than two.
        try fixture.store.write("10.0.0.9\tlocalhost\n", to: "fragments/project.hosts")
        XCTAssertEqual(writeState(fixture, helper: .enabled), .pending(entries: 1))
    }

    func testAnUnreadableLiveFileIsBlockedWithItsReason() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.live.url)

        let state = writeState(fixture, helper: .enabled)

        guard case .blocked(let cause, let remedy) = state else {
            return XCTFail("expected blocked, got \(state)")
        }
        XCTAssertTrue(cause.contains("could not be read"), cause)
        XCTAssertNil(remedy, "nothing in the window fixes a missing file")
    }

    func testMarkersThatCannotBeReadBlockWithTheirReason() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        try fixture.live.write(
            bytes("# >>> hazmat:managed v1 >>>\n10.1.2.3 a.example\n# >>> hazmat:managed v1 >>>\n")
        )

        let state = writeState(fixture, helper: .enabled)

        guard case .blocked(let cause, let remedy) = state else {
            return XCTFail("expected blocked, got \(state)")
        }
        XCTAssertTrue(cause.contains("markers"), cause)
        XCTAssertNil(remedy)
    }

    // MARK: - The helper's state

    func testAPendingWriteIsBlockedWithoutAnEnabledHelperAndOffersInstallingIt() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        for helper in [HelperState.notRegistered, .awaitingApproval] {
            let state = writeState(fixture, helper: helper)
            guard case .blocked(let cause, let remedy) = state else {
                return XCTFail("expected blocked for \(helper), got \(state)")
            }
            XCTAssertTrue(cause.contains("helper"), cause)
            XCTAssertEqual(remedy, .installHelper)
        }
    }

    func testAnAppliedBlockIsInSyncEvenWhenTheHelperCannotWrite() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        try fixture.applyToLive(work)

        XCTAssertEqual(writeState(fixture, helper: .notRegistered), .inSync)
    }

    // MARK: - Nothing to write

    func testAProfileWithNoLayersIsBlockedUntilOneIsAdded() throws {
        let fixture = try fixture(layers: "")
        defer { fixture.remove() }

        let state = writeState(fixture, helper: .enabled)

        guard case .blocked(let cause, let remedy) = state else {
            return XCTFail("expected blocked, got \(state)")
        }
        XCTAssertTrue(cause.contains("no layers"), cause)
        XCTAssertEqual(remedy, .addFragment)
    }

    func testAProfileThatCannotResolveIsBlockedWithItsProblem() throws {
        let fixture = try fixture(layers: "base\nmissing\n")
        defer { fixture.remove() }

        let state = writeState(fixture, helper: .enabled)

        guard case .blocked(let cause, let remedy) = state else {
            return XCTFail("expected blocked, got \(state)")
        }
        XCTAssertTrue(cause.contains("missing"), cause)
        XCTAssertNil(remedy)
    }

    func testAMissingStoreIsBlockedUntilItIsCreated() throws {
        let store = try TemporaryStore()
        let root = store.root
        store.remove()
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let model = EditorModel(storeRoot: root, fileURL: live.url, writer: UnregisteredHelper())

        let state = model.read().writeState(helper: .enabled)

        guard case .blocked(let cause, let remedy) = state else {
            return XCTFail("expected blocked, got \(state)")
        }
        XCTAssertTrue(cause.contains("no store"), cause)
        XCTAssertEqual(remedy, .createStore)
    }

    // MARK: - Every state carries a glyph, a word and a tone

    func testEveryWriteStateCarriesAGlyphAWordAndATone() {
        let states: [WriteState] = [
            .inSync,
            .pending(entries: 3),
            .blocked(cause: "because", remedy: .installHelper)
        ]

        XCTAssertEqual(states.map(\.label), ["In sync", "3 changes pending", "Blocked"])
        XCTAssertEqual(Set(states.map(\.symbolName)).count, 3)
        XCTAssertEqual(states.map(\.tone), [.success, .warning, .danger])
        XCTAssertEqual(WriteState.pending(entries: 1).label, "1 change pending")
    }
}
