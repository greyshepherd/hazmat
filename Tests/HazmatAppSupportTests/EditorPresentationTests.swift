import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

/// The moment the reads in this file are answered from, so "out of date" is a
/// value rather than the day the suite happens to run.
private let readAt = Date(timeIntervalSince1970: 1_760_000_000)

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

    // MARK: - A read for a window that is not showing

    /// With no window showing, a read carries what the menu and the schedule
    /// need — the rendered block, its entry count, what the live file holds —
    /// and not the composition or the fragment's text, which only the panes
    /// show and which are what a large fragment costs.
    func testAReadWithoutDetailCarriesTheRenderingButNotTheCompositionOrTheText() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())
        let full = model.read(selection: .profile(work))

        let slim = model.read(selection: .profile(work), detail: false)

        XCTAssertEqual(slim.rendering, full.rendering)
        XCTAssertEqual(slim.entryCount, full.entryCount)
        XCTAssertEqual(slim.live, full.live)
        XCTAssertEqual(slim.appliedProfiles, full.appliedProfiles)
        XCTAssertEqual(slim.profileRows, full.profileRows)
        XCTAssertEqual(slim.fragmentRows, full.fragmentRows)
        XCTAssertEqual(slim.layers, full.layers)
        XCTAssertFalse(slim.hasDetail)
        XCTAssertTrue(full.hasDetail)
        XCTAssertNil(slim.resolved.composition, "the composition is the panes' alone")
        XCTAssertTrue(slim.entries.isEmpty)
        XCTAssertTrue(slim.problems.isEmpty)
        XCTAssertEqual(slim.writeState(helper: .notRegistered), full.writeState(helper: .notRegistered))

        let fragment = model.read(selection: .fragment(project), detail: false)
        XCTAssertEqual(fragment.selectedFragment, project)
        XCTAssertEqual(fragment.fragmentText, "", "the text is decoded for the editor, not for a closed window")
        XCTAssertEqual(fragment.stacks(project), [work])
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

    // MARK: - A source's origin reaches the reading

    func testASourceWhoseFragmentIsNotThereYetStillHasARowWithItsReason() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        // A first fetch that failed: a sidecar, a reason, and no fragment.
        try fixture.writeSource(
            FragmentID("blocklist"),
            url: "https://example.com/hosts.txt",
            interval: 6 * 3600,
            lastAttempt: readAt,
            lastFailure: "the server answered 503"
        )
        let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

        let presentation = model.read(selection: .fragment(FragmentID("blocklist")))

        XCTAssertEqual(presentation.fragments.map(\.rawValue), ["base", "blocklist", "project"])
        let row = try XCTUnwrap(presentation.fragmentRow(FragmentID("blocklist")))
        XCTAssertEqual(row.fragment, FragmentID("blocklist"))
        XCTAssertEqual(row.entryCount, 0, "the store holds no text for it")
        XCTAssertTrue(row.isRemote)
        XCTAssertEqual(row.origin?.url, URL(string: "https://example.com/hosts.txt"))
        XCTAssertEqual(row.origin?.interval, 6 * 3600)
        XCTAssertEqual(row.origin?.lastSuccess, nil)
        XCTAssertEqual(row.origin?.failure, "the server answered 503")
        XCTAssertTrue(row.origin?.isOutOfDate ?? false, "a source that never refreshed is out of date")
        XCTAssertFalse(row.origin?.isBroken ?? true)
        XCTAssertEqual(presentation.fragmentText, "", "there is no text to edit yet")
        XCTAssertEqual(presentation.selectedFragment, FragmentID("blocklist"))
        XCTAssertTrue(presentation.isRemote(FragmentID("blocklist")))
    }

    func testAnOrdinaryFragmentHasNoOriginAndASourceCarriesItsRefreshState() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        try fixture.writeSource(
            base,
            url: "https://example.com/base.txt",
            interval: 6 * 3600,
            lastAttempt: readAt,
            lastSuccess: readAt
        )
        let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

        let presentation = model.read(selection: .fragment(base))

        let remote = try XCTUnwrap(presentation.fragmentRow(base))
        XCTAssertEqual(remote.origin?.url, URL(string: "https://example.com/base.txt"))
        XCTAssertEqual(remote.origin?.lastSuccess, readAt)
        XCTAssertNil(remote.origin?.failure)
        XCTAssertFalse(remote.origin?.isOutOfDate ?? true, "it refreshed a moment ago")
        XCTAssertEqual(remote.entryCount, 1, "the text is the fragment's own")

        let ordinary = try XCTUnwrap(presentation.fragmentRow(project))
        XCTAssertFalse(ordinary.isRemote)
        XCTAssertNil(ordinary.origin)
        XCTAssertFalse(presentation.isRemote(project))
    }

    func testASourceThatIsOutOfDateSaysSoAndOneInsideItsIntervalDoesNot() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        try fixture.writeSource(base, url: "https://example.com/base.txt", interval: 3600, lastAttempt: readAt, lastSuccess: readAt)
        try fixture.writeSource(
            project,
            url: "https://example.com/project.txt",
            interval: 6 * 3600,
            lastAttempt: readAt.addingTimeInterval(-7 * 3600),
            lastSuccess: readAt.addingTimeInterval(-7 * 3600)
        )
        let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

        let presentation = model.read(selection: .fragment(base))

        XCTAssertFalse(presentation.origin(of: base)?.isOutOfDate ?? true, "inside its interval")
        XCTAssertFalse(presentation.origin(of: base)?.isBroken ?? true)
        XCTAssertTrue(presentation.origin(of: project)?.isOutOfDate ?? false, "the interval has elapsed")
        XCTAssertFalse(presentation.origin(of: project)?.isBroken ?? true)
    }

    func testASidecarThatCannotBeReadIsARowWithAReasonAndNoURL() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        try fixture.store.write("{\"version\": 99, \"url\": \"https://example.com/x.txt\", \"interval\": 60}", to: "remote/blocklist.remote")
        let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

        let presentation = model.read()

        let row = try XCTUnwrap(presentation.fragmentRow(FragmentID("blocklist")))
        XCTAssertTrue(row.isRemote, "the store holds a sidecar, so it is a source")
        XCTAssertNil(row.origin?.url)
        XCTAssertNil(row.origin?.host, "there is no domain to name when the origin cannot be read")
        XCTAssertTrue(row.origin?.isBroken ?? false)
        XCTAssertTrue(row.origin?.failure?.contains("99") ?? false, row.origin?.failure ?? "no reason")
        XCTAssertTrue(row.origin?.isOutOfDate ?? false)
    }

    func testARemoteFragmentOffersNoSaveButTheRefreshActionAndAnOrdinaryOneTheReverse() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        try fixture.writeSource(base, url: "https://example.com/base.txt", interval: 6 * 3600)
        let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

        let remote = model.read(selection: .fragment(base))
        XCTAssertTrue(remote.actions.contains(.refreshSource(base)), "\(remote.actions)")
        XCTAssertFalse(
            remote.actions.contains(.saveFragment(base)),
            "a remote fragment's text is read-only, because the next refresh replaces it"
        )
        XCTAssertTrue(remote.actions.contains(.renameFragment(base)), "renaming carries the origin")
        XCTAssertTrue(remote.actions.contains(.duplicateFragment(base)), "the copy is an ordinary fragment")

        let ordinary = model.read(selection: .fragment(project))
        XCTAssertTrue(ordinary.actions.contains(.saveFragment(project)))
        XCTAssertFalse(ordinary.actions.contains { if case .refreshSource = $0 { return true }; return false })
    }

    func testTheRowNamesTheDomainWhateverTheURLsShape() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let cases: [(url: String, host: String)] = [
            ("https://someonewhocares.org/hosts/zero/hosts", "someonewhocares.org"),
            ("https://example.com", "example.com"),
            ("https://www.example.co.uk/a/b?c=d", "www.example.co.uk"),
            ("https://mirror.example.com:8443/hosts.txt", "mirror.example.com"),
            ("https://user@example.com/hosts.txt", "example.com")
        ]

        for (index, entry) in cases.enumerated() {
            let name = FragmentID("source\(index)")
            try fixture.writeSource(name, url: entry.url, interval: 6 * 3600)
            let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

            let origin = try XCTUnwrap(model.read().origin(of: name))
            XCTAssertEqual(origin.host, entry.host, entry.url)
            XCTAssertEqual(origin.url?.absoluteString, entry.url, "the whole address is still the origin's")
        }
    }

    func testAFetchedFragmentIsCountedLikeAPastedOne() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        // `base` holds one entry and is a source; `project` holds two and is not.
        try fixture.writeSource(base, url: "https://example.com/base.txt", interval: 6 * 3600, lastSuccess: readAt)
        let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

        let presentation = model.read()

        XCTAssertEqual(presentation.fragmentRow(base)?.entryCountPhrase, "1 entry", "a fetched fragment is counted too")
        XCTAssertEqual(presentation.fragmentRow(project)?.entryCountPhrase, "2 entries")
        XCTAssertTrue(presentation.fragmentRow(base)?.hasText ?? false)
    }

    func testASourceWithNoTextYetHasNoCountToShow() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        // A first fetch that failed: a sidecar and no fragment.
        try fixture.writeSource(
            FragmentID("blocklist"),
            url: "https://example.com/hosts.txt",
            interval: 6 * 3600,
            lastFailure: "the server answered 503"
        )
        let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

        let row = try XCTUnwrap(model.read().fragmentRow(FragmentID("blocklist")))

        XCTAssertTrue(row.isRemote, "it is still a row, with its own line saying why")
        XCTAssertFalse(row.hasText)
        XCTAssertEqual(row.entryCount, 0)
        XCTAssertNil(row.entryCountPhrase, "there is nothing to count yet, so the row says nothing")
    }

    func testAFragmentThatIsThereAndEmptyCountsZeroWhileOneThatIsNotThereShowsNothing() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let empty = FragmentID("empty")
        let missing = FragmentID("missing")
        try fixture.store.write("", to: "fragments/empty.hosts")
        try fixture.writeSource(missing, url: "https://example.com/missing.txt", interval: 6 * 3600)
        let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

        let presentation = model.read()

        XCTAssertEqual(
            presentation.fragmentRow(empty)?.entryCountPhrase,
            "0 entries",
            "a fragment that is there and holds nothing is counted"
        )
        XCTAssertNil(
            presentation.fragmentRow(missing)?.entryCountPhrase,
            "a fragment that is not there has a reason instead of a count"
        )
    }

    func testASourceWhoseTextIsNotThereYetOffersTheRefreshAndNoSave() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        try fixture.writeSource(
            FragmentID("blocklist"),
            url: "https://example.com/hosts.txt",
            interval: 6 * 3600,
            lastFailure: "the server answered 503"
        )
        let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

        let presentation = model.read(selection: .fragment(FragmentID("blocklist")))

        XCTAssertTrue(presentation.actions.contains(.refreshSource(FragmentID("blocklist"))))
        XCTAssertFalse(presentation.actions.contains(.saveFragment(FragmentID("blocklist"))))
        XCTAssertEqual(presentation.fragmentText, "")
    }

    func testARowNamesTheURLLastSuccessOutOfDateStateAndFailure() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        // A marked row that refreshed inside its interval.
        try fixture.writeSource(
            base,
            url: "https://example.com/base.txt?mirror=eu",
            interval: 6 * 3600,
            lastAttempt: readAt,
            lastSuccess: readAt
        )
        // An out-of-date row.
        try fixture.writeSource(
            project,
            url: "https://example.com/project.txt",
            interval: 3600,
            lastAttempt: readAt.addingTimeInterval(-2 * 3600),
            lastSuccess: readAt.addingTimeInterval(-2 * 3600)
        )
        let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

        let presentation = model.read()

        let marked = try XCTUnwrap(presentation.origin(of: base))
        XCTAssertEqual(marked.url?.absoluteString, "https://example.com/base.txt?mirror=eu")
        XCTAssertEqual(marked.host, "example.com", "the row names the domain, not the whole address")
        XCTAssertTrue(marked.state.hasPrefix("Refreshed "), marked.state)
        XCTAssertFalse(marked.state.contains("Out of date"), marked.state)

        let stale = try XCTUnwrap(presentation.origin(of: project))
        XCTAssertEqual(stale.url?.absoluteString, "https://example.com/project.txt")
        XCTAssertTrue(stale.state.contains("Out of date"), stale.state)
    }

    func testARowReportsTheReasonTheLastRefreshFailed() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        try fixture.writeSource(
            base,
            url: "https://example.com/base.txt",
            interval: 6 * 3600,
            lastAttempt: readAt,
            lastSuccess: readAt.addingTimeInterval(-7 * 3600),
            lastFailure: "the exchange timed out"
        )
        let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

        let origin = try XCTUnwrap(model.read().origin(of: base))

        XCTAssertTrue(origin.state.contains("the exchange timed out"), origin.state)
        XCTAssertTrue(origin.state.contains("Out of date"), origin.state)
        XCTAssertEqual(origin.failure, "the exchange timed out")
    }

    func testASourceThatWasNeverRefreshedSaysSoAndOneInsideItsIntervalDoesNot() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        try fixture.writeSource(base, url: "https://example.com/base.txt", interval: 6 * 3600)
        let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

        let origin = try XCTUnwrap(model.read().origin(of: base))

        XCTAssertTrue(origin.state.contains("Never refreshed"), origin.state)
        XCTAssertTrue(origin.state.contains("Out of date"), origin.state)
        XCTAssertNil(origin.failure)
    }

    func testAnEmptyStoreWithNoSourcesReadsAsBefore() throws {
        let fixture = try twoLayerFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper(), now: { readAt })

        let presentation = model.read()

        XCTAssertEqual(presentation.fragments, [base, project])
        XCTAssertTrue(presentation.fragmentRows.allSatisfy { !$0.isRemote })
    }
}
