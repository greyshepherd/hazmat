import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

/// The values the panes render: the live file's path, entry and layer counts,
/// per-layer counts, a fragment's using profiles, and search.
final class EditorPresentationTests: XCTestCase {
    private let base = FragmentID("base")
    private let project = FragmentID("project")
    private let work = ProfileID("work")
    private let other = ProfileID("other")

    private func twoLayerFixture() throws -> StoreFixture {
        try StoreFixture(
            store: [
                ("127.0.0.1\tlocalhost alpha.example\n", "fragments/base.hosts"),
                ("10.0.0.9\talpha.example\n127.0.0.1\tbeta.example\n", "fragments/project.hosts"),
                ("base\nproject\n", "profiles/work.profile"),
                ("base\n", "profiles/other.profile")
            ],
            live: "127.0.0.1\tlocalhost\n"
        )
    }

    // MARK: - 1.3 The hosts file path, the entry count and the layer count

    func testThePresentationNamesTheLiveFileAndCountsTheProfile() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .profile(work))

        XCTAssertEqual(presentation.hostsFilePath, fixture.live.url.path)
        XCTAssertEqual(presentation.layerCount, 2)
        XCTAssertEqual(presentation.layers, [base, project])
        // localhost, alpha.example (overridden) and beta.example.
        XCTAssertEqual(presentation.entryCount, 3)
        XCTAssertEqual(
            presentation.entryLines.map(\.address),
            ["127.0.0.1", "10.0.0.9", "127.0.0.1"]
        )
        XCTAssertEqual(
            presentation.entryLines.map { $0.names.joined(separator: " ") },
            ["localhost", "alpha.example", "beta.example"]
        )
        XCTAssertEqual(
            presentation.entryLines.map(\.source.fragment),
            [base, project, project]
        )
    }

    // MARK: - 1.4 Per-layer entry counts

    func testEachLayerReportsTheEntriesItHolds() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .profile(work))

        XCTAssertEqual(presentation.layerRows.map(\.position), [1, 2])
        XCTAssertEqual(presentation.layerRows.map(\.fragment), [base, project])
        XCTAssertEqual(presentation.layerRows.map(\.entryCount), [1, 2])
    }

    func testAFragmentRowReportsTheEntriesTheFragmentHolds() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .profile(work))

        XCTAssertEqual(presentation.fragmentRows.map(\.fragment), [base, project])
        XCTAssertEqual(presentation.fragmentRows.map(\.entryCount), [1, 2])
        XCTAssertEqual(presentation.entryCount(of: project), 2)
    }

    // MARK: - 1.5 A fragment's using profiles

    func testAFragmentUsedByTwoProfilesNamesBoth() throws {
        let fixture = try StoreFixture(
            store: [
                ("127.0.0.1\tlocalhost\n", "fragments/base.hosts"),
                ("base\n", "profiles/one.profile"),
                ("base\n", "profiles/two.profile")
            ],
            live: "127.0.0.1\tlocalhost\n"
        )
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .fragment(base))

        XCTAssertEqual(presentation.usingProfiles.map(\.rawValue), ["one", "two"])
    }

    func testAFragmentNoProfileUsesSaysSo() throws {
        let fixture = try StoreFixture(
            store: [
                ("127.0.0.1\tlocalhost\n", "fragments/base.hosts"),
                ("0.0.0.0\tads.example\n", "fragments/ads.hosts"),
                ("base\n", "profiles/work.profile")
            ],
            live: "127.0.0.1\tlocalhost\n"
        )
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .fragment(FragmentID("ads")))

        XCTAssertEqual(presentation.usingProfiles, [])
    }

    // MARK: - 1.6 Search

    func testASearchNarrowsBothSectionsAndKeepsAMatchingSelection() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .fragment(project), search: StoreSearch(text: "proj"))

        XCTAssertEqual(presentation.profileRows, [], "the search matches a profile by its own name")
        XCTAssertEqual(presentation.fragmentRows.map(\.fragment), [project])
        XCTAssertEqual(presentation.selection, .fragment(project), "a matching selection stays selected")
        XCTAssertEqual(presentation.fragmentText, "10.0.0.9\talpha.example\n127.0.0.1\tbeta.example\n")
        XCTAssertNil(presentation.hiddenSelection)
    }

    func testASearchThatHidesTheSelectionSelectsNothing() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .profile(work), search: StoreSearch(text: "project"))

        XCTAssertNil(presentation.selection, "a hidden item is not edited")
        XCTAssertEqual(presentation.hiddenSelection, .profile(work))
        XCTAssertEqual(presentation.fragmentRows.map(\.fragment), [project])
        XCTAssertTrue(presentation.profileRows.isEmpty)
    }

    func testClearingTheSearchListsEverythingAgain() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let narrowed = model.read(selection: .fragment(project), search: StoreSearch(text: "proj"))
        XCTAssertEqual(narrowed.fragmentRows.count, 1)

        let cleared = model.read(selection: .fragment(project), search: .none)

        XCTAssertEqual(cleared.fragmentRows.map(\.fragment), [base, project])
        XCTAssertEqual(cleared.profileRows.map(\.profile), [other, work])
        XCTAssertEqual(cleared.selection, .fragment(project))
    }

    func testASearchMatchesCaseInsensitivelyAndAnywhereInTheName() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        XCTAssertEqual(
            model.read(selection: nil, search: StoreSearch(text: "PROJ")).fragmentRows.map(\.fragment),
            [project]
        )
        XCTAssertEqual(
            model.read(selection: nil, search: StoreSearch(text: "oj")).fragmentRows.map(\.fragment),
            [project]
        )
    }

    func testASelectionTheStoreNoLongerHoldsFallsBackToTheFirstItem() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .profile(ProfileID("deleted")))

        XCTAssertEqual(presentation.selection, .profile(other))
        XCTAssertEqual(presentation.selectedProfile, other)
    }

    // MARK: - What fills the content pane

    func testTheContentPaneEditsTheSelectedItemWhateverThePhase() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let profile = model.read(selection: .profile(work))
        XCTAssertEqual(profile.content(phase: .changesPending), .profile(work))

        let fragment = model.read(selection: .fragment(base))
        XCTAssertEqual(fragment.content(phase: .inSync), .fragment(base))
    }

    func testAFragmentInAStoreWithNoProfilesStillFillsTheContentPane() throws {
        let store = try TemporaryStore()
        let root = store.root
        store.remove()
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let model = EditorModel(storeRoot: root, fileURL: live.url, writer: UnregisteredHelper())
        XCTAssertEqual(model.createFragment(named: "base").store, .success(.wrote))

        let presentation = model.read(selection: .fragment(base))

        XCTAssertEqual(presentation.content(phase: .noProfiles), .fragment(base))
        XCTAssertEqual(
            presentation.content(phase: .noStore),
            .fragment(base),
            "an item the store holds is edited even when the phase still says no store"
        )
    }

    func testThePhaseFillsTheContentPaneWhenNothingIsSelected() throws {
        let store = try TemporaryStore()
        let root = store.root
        store.remove()
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let model = EditorModel(storeRoot: root, fileURL: live.url, writer: UnregisteredHelper())

        XCTAssertEqual(model.read().content(phase: .noStore), .phase(.noStore))
    }

    func testASearchThatHidesTheSelectionLeavesThePhaseInTheContentPane() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .profile(work), search: StoreSearch(text: "project"))

        XCTAssertEqual(presentation.content(phase: .nothingSelected), .phase(.nothingSelected))
    }

    // MARK: - The applied marks

    func testEachProfileRowReportsWhetherItsBlockIsTheLiveOne() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        try fixture.applyToLive(work)

        let presentation = fixture.model(writer: UnregisteredHelper()).read(selection: .profile(work))

        XCTAssertEqual(presentation.appliedProfiles, [work])
        XCTAssertEqual(presentation.profileRows.map(\.isApplied), [false, true])
        XCTAssertTrue(presentation.isApplied(work))
        XCTAssertFalse(presentation.isApplied(other))
    }
}
