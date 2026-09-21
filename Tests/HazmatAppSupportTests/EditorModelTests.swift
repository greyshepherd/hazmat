import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

private let work = ProfileID("work")
private let other = ProfileID("other")

final class EditorModelTests: XCTestCase {
    private let base = FragmentID("base")
    private let project = FragmentID("project")
    private let ads = FragmentID("ads")

    private func stackedFixture() throws -> StoreFixture {
        try StoreFixture(
            store: [
                ("127.0.0.1\tlocalhost alpha.example\n", "fragments/base.hosts"),
                ("10.0.0.9\talpha.example\n", "fragments/project.hosts"),
                ("base\nproject\n", "profiles/work.profile"),
                ("base\n", "profiles/other.profile")
            ],
            live: "127.0.0.1\tlocalhost\n"
        )
    }

    // MARK: - 3.1 The store as it is now

    func testAFragmentCreatedOutsideTheApplicationAppearsInALaterRead() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let first = model.read()
        XCTAssertEqual(first.fragments, [base, project])

        try fixture.store.write("0.0.0.0\tads.example.com\n", to: "fragments/ads.hosts")

        let second = model.read()
        XCTAssertEqual(second.fragments.map(\.rawValue), ["ads", "base", "project"])
        XCTAssertEqual(second.profiles, [other, work])
    }

    func testAStoreThatDoesNotExistReadsAsAnEmptyStore() throws {
        let store = try TemporaryStore()
        let root = store.root
        store.remove()
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let model = EditorModel(storeRoot: root, fileURL: live.url, writer: UnregisteredHelper())

        let presentation = model.read()

        XCTAssertFalse(presentation.storeExists)
        XCTAssertEqual(presentation.profiles, [])
        XCTAssertEqual(presentation.fragments, [])
        XCTAssertNil(presentation.selectedProfile)
        XCTAssertNil(presentation.selectedFragment)
        XCTAssertEqual(presentation.fragmentText, "")
        XCTAssertEqual(presentation.entries, [])
        XCTAssertEqual(presentation.layers, [])
        XCTAssertTrue(presentation.actions.contains(.newProfile))
        XCTAssertTrue(presentation.actions.contains(.newFragment))
    }

    func testAStoreThatHoldsOnlyAFragmentStillReadsAsAStore() throws {
        let store = try TemporaryStore()
        let root = store.root
        store.remove()
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let model = EditorModel(storeRoot: root, fileURL: live.url, writer: UnregisteredHelper())
        XCTAssertEqual(model.createFragment(named: "base").store, .success(.wrote))

        let presentation = model.read()

        XCTAssertTrue(presentation.storeExists, "the store holds the fragment that was just created")
        XCTAssertEqual(presentation.profiles, [])
        XCTAssertEqual(presentation.fragments, [base])
        XCTAssertEqual(presentation.selection, .fragment(base))
        XCTAssertEqual(presentation.fragmentText, "")
    }

    func testTheSelectedFragmentsTextIsLoadedFromTheStore() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .fragment(project))

        XCTAssertEqual(presentation.selectedFragment, project)
        XCTAssertEqual(presentation.fragmentText, "10.0.0.9\talpha.example\n")
        XCTAssertEqual(presentation.selectedProfile, other, "the first profile is selected when none is asked for")
        XCTAssertEqual(presentation.layers, [base])
    }

    // MARK: - 3.2 The resolved view

    func testEveryEntryNamesTheFragmentItCameFrom() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .profile(work))

        XCTAssertEqual(presentation.entries.map(\.name), ["localhost", "alpha.example"])
        XCTAssertEqual(
            presentation.entries.map(\.source),
            [SourceLocation(fragment: base, line: 1), SourceLocation(fragment: project, line: 1)]
        )
    }

    func testAnOverrideIsExplainedWithBothFragments() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .profile(work))

        XCTAssertEqual(presentation.entries.first { $0.name == "alpha.example" }?.address, "10.0.0.9")
        XCTAssertEqual(presentation.displacements.count, 1)
        let displacement = try XCTUnwrap(presentation.displacements.first)
        XCTAssertEqual(displacement.name, "alpha.example")
        XCTAssertEqual(displacement.address, "127.0.0.1")
        XCTAssertEqual(displacement.source.fragment, base)
        XCTAssertEqual(displacement.displacedBy.fragment, project)
    }

    func testAMalformedLineIsReportedWithItsFragmentAndLine() throws {
        let fixture = try StoreFixture(
            store: [
                ("127.0.0.1\tlocalhost\nnot an entry\n", "fragments/base.hosts"),
                ("base\n", "profiles/work.profile")
            ],
            live: "127.0.0.1\tlocalhost\n"
        )
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .profile(work))

        XCTAssertTrue(presentation.entries.isEmpty)
        XCTAssertEqual(presentation.resolved.problems.count, 1)
        let located = presentation.problems.compactMap { problem -> (FragmentID, Int)? in
            guard case .malformedEntry(let fragment, let line, _, _) = problem else { return nil }
            return (fragment, line)
        }
        XCTAssertEqual(located.count, 1)
        XCTAssertEqual(located.first?.0, base)
        XCTAssertEqual(located.first?.1, 2)
    }

    func testAProfileThatCannotResolveShowsNoEntriesAndNamesTheMissingFragment() throws {
        let fixture = try StoreFixture(
            store: [
                ("base\nmissing\n", "profiles/work.profile"),
                ("127.0.0.1\tlocalhost\n", "fragments/base.hosts")
            ],
            live: "127.0.0.1\tlocalhost\n"
        )
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let presentation = model.read(selection: .profile(work))

        XCTAssertEqual(presentation.entries, [])
        XCTAssertTrue(presentation.problems.contains { $0.message.contains("missing") }, presentation.problems.description)
        XCTAssertNil(presentation.rendering, "an unresolvable profile renders nothing")
    }

    func testTwoReadsProduceEqualViews() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let first = model.read(selection: .profile(work))
        let again = model.read(selection: .profile(work))

        XCTAssertEqual(first, again)
        XCTAssertEqual(first.entries, again.entries)
        XCTAssertEqual(first.displacements, again.displacements)
    }

    // MARK: - 3.3 The layer stack

    func testReorderingChangesWhichLayerWins() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())
        let before = model.read(selection: .profile(work))
        XCTAssertEqual(before.entries.first { $0.name == "alpha.example" }?.address, "10.0.0.9")

        let outcome = model.moveLayer(from: 1, to: 0, in: work, previous: before)

        XCTAssertEqual(outcome.store, .success(.wrote))
        XCTAssertEqual(try fixture.text("profiles/work.profile"), "project\nbase\n")
        let after = model.read(selection: .profile(work))
        XCTAssertEqual(after.layers, [project, base])
        XCTAssertEqual(after.entries.first { $0.name == "alpha.example" }?.address, "127.0.0.1")
        XCTAssertEqual(after.displacements.count, 1)
        XCTAssertEqual(after.displacements.first?.displacedBy.fragment, base)
    }

    func testAddingAndRemovingALayerChangesTheResolvedView() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())
        var presentation = model.read(selection: .profile(work))

        let removed = model.removeLayer(at: 1, from: work, previous: presentation)
        XCTAssertEqual(removed.store, .success(.wrote))
        presentation = model.read(selection: .profile(work))
        XCTAssertEqual(presentation.layers, [base])
        XCTAssertTrue(presentation.displacements.isEmpty)
        XCTAssertEqual(presentation.entries.map(\.name), ["localhost", "alpha.example"])
        XCTAssertEqual(presentation.entries.first { $0.name == "alpha.example" }?.address, "127.0.0.1")

        let added = model.addLayer(project, to: work, previous: presentation)
        XCTAssertEqual(added.store, .success(.wrote))
        presentation = model.read(selection: .profile(work))
        XCTAssertEqual(presentation.layers, [base, project])
        XCTAssertEqual(presentation.entries.first { $0.name == "alpha.example" }?.address, "10.0.0.9")
        XCTAssertEqual(try fixture.text("profiles/work.profile"), "base\nproject\n")
    }

    func testEveryLayerRemovedRendersAnEmptyBlockRatherThanFailing() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let first = model.removeLayer(at: 0, from: work, previous: model.read(selection: .profile(work)))
        XCTAssertEqual(first.store, .success(.wrote))
        let second = model.removeLayer(at: 0, from: work, previous: model.read(selection: .profile(work)))
        XCTAssertEqual(second.store, .success(.wrote))

        let empty = model.read(selection: .profile(work))
        XCTAssertEqual(empty.layers, [])
        XCTAssertEqual(empty.entries, [])
        let rendered = try XCTUnwrap(empty.rendering)
        XCTAssertEqual(text(rendered), "# >>> hazmat:managed v1 >>>\n# <<< hazmat:managed v1 <<<\n")
    }

    // MARK: - 3.4 Saving and the re-apply rule

    func testEditingTheAppliedProfileRewritesTheLiveBlock() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let writer = LocalWriter(target: fixture.live.url)
        let model = fixture.model(writer: writer)
        try fixture.applyToLive(work)
        let before = model.read(selection: .profile(work))
        XCTAssertTrue(before.isApplied)

        let outcome = model.save(
            fragment: base,
            text: "127.0.0.1\tchanged.example\n",
            editing: work,
            previous: before
        )

        XCTAssertEqual(outcome.store, .success(.wrote))
        XCTAssertEqual(outcome.apply, .applied(.replacedBlock(overwroteDrift: true)))
        XCTAssertEqual(writer.writes, 1)
        XCTAssertEqual(try fixture.text("fragments/base.hosts"), "127.0.0.1\tchanged.example\n")

        let live = try XCTUnwrap(ManagedBlock.locate(in: fixture.live.data))
        XCTAssertEqual(Data(fixture.live.data[live.range]), try fixture.rendered(work))
        XCTAssertEqual(text(try BlockSplice.strip(from: fixture.live.data)), "127.0.0.1\tlocalhost\n")
        let after = model.read(selection: .profile(work))
        XCTAssertTrue(after.isApplied, "the file holds the block the edited profile renders now")
        XCTAssertTrue(after.entries.contains { $0.name == "changed.example" })
    }

    func testAChangedLiveBlockLeavesTheFileAloneAndReportsDrift() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let writer = LocalWriter(target: fixture.live.url)
        let model = fixture.model(writer: writer)
        try fixture.applyToLive(work)
        let before = model.read(selection: .profile(work))
        XCTAssertTrue(before.isApplied)

        // Another tool changes a line inside the block.
        let changed = bytes(text(fixture.live.data).replacingOccurrences(of: "alpha.example", with: "moved.example"))
        try fixture.live.write(changed)

        let outcome = model.save(
            fragment: base,
            text: "127.0.0.1\tchanged.example\n",
            editing: work,
            previous: before
        )

        XCTAssertEqual(outcome.store, .success(.wrote), "the store change survives the refused apply")
        XCTAssertEqual(outcome.apply, .refused(.driftNotOverwritten))
        XCTAssertTrue(outcome.description.contains("drift"), outcome.description)
        XCTAssertEqual(writer.writes, 0)
        XCTAssertEqual(fixture.live.data, changed, "the live file is left as it is")
        XCTAssertEqual(try fixture.text("fragments/base.hosts"), "127.0.0.1\tchanged.example\n")
    }

    func testEditingAProfileThatIsNotAppliedLeavesTheLiveFileAlone() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let writer = LocalWriter(target: fixture.live.url)
        let model = fixture.model(writer: writer)
        try fixture.applyToLive(work)
        let liveBefore = try fixture.live.state()

        let otherProfile = model.read(selection: .profile(other))
        XCTAssertFalse(otherProfile.isApplied)
        let outcome = model.save(
            fragment: base,
            text: "127.0.0.1\tchanged.example\n",
            editing: other,
            previous: otherProfile
        )

        XCTAssertEqual(outcome.store, .success(.wrote))
        XCTAssertNil(outcome.apply, "a profile that is not applied never reaches the live file")
        XCTAssertEqual(writer.writes, 0)
        XCTAssertEqual(try fixture.live.state(), liveBefore)
    }

    func testARefusedApplyLeavesTheStoreChangeInPlaceAndReportsTheReason() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let helper = UnregisteredHelper()
        let model = fixture.model(writer: helper)
        try fixture.applyToLive(work)
        let before = model.read(selection: .profile(work))
        let liveBefore = try fixture.live.state()

        let outcome = model.save(
            fragment: base,
            text: "127.0.0.1\tchanged.example\n",
            editing: work,
            previous: before
        )

        XCTAssertEqual(outcome.store, .success(.wrote))
        XCTAssertEqual(outcome.apply, .refused(.privileged("the helper is not registered")))
        XCTAssertTrue(outcome.description.contains("not registered"), outcome.description)
        XCTAssertEqual(try fixture.live.state(), liveBefore)
        XCTAssertEqual(try fixture.text("fragments/base.hosts"), "127.0.0.1\tchanged.example\n")
    }

    func testASavedFragmentInAStoreWithNoProfileReachesTheStoreAlone() throws {
        let store = try TemporaryStore()
        let root = store.root
        store.remove()
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let helper = UnregisteredHelper()
        let model = EditorModel(storeRoot: root, fileURL: live.url, writer: helper)
        let liveBefore = try live.state()
        XCTAssertEqual(model.createFragment(named: "base").store, .success(.wrote))

        let outcome = model.save(
            fragment: base,
            text: "127.0.0.1\tchanged.example\n",
            editing: nil,
            previous: model.read(selection: .fragment(base))
        )

        XCTAssertEqual(outcome.store, .success(.wrote))
        XCTAssertNil(outcome.apply, "a store with no profile has no block to re-apply")
        XCTAssertEqual(helper.requests, 0, "authoring must not ask the helper for anything")
        XCTAssertEqual(try store.text("fragments/base.hosts"), "127.0.0.1\tchanged.example\n")
        XCTAssertEqual(try live.state(), liveBefore)
    }

    // MARK: - 3.5 A rename carries its references

    func testRenamingAFragmentLeavesTheProfilesThatStackItResolving() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let before = model.read(selection: .fragment(base))
        XCTAssertEqual(before.usingProfiles, [other, work])

        XCTAssertEqual(model.rename(fragment: base, to: "renamed").store, .success(.wrote))

        let renamed = model.read(selection: .fragment(FragmentID("renamed")))
        XCTAssertEqual(renamed.usingProfiles, [other, work])
        XCTAssertEqual(renamed.entryCount(of: FragmentID("renamed")), 1)

        let profile = model.read(selection: .profile(work))
        XCTAssertEqual(profile.layers.map(\.rawValue), ["renamed", "project"])
        XCTAssertEqual(profile.problems, [], "no layer is left naming a fragment that is gone")
        XCTAssertEqual(profile.entryCount, 2)
        XCTAssertEqual(try fixture.store.text("profiles/work.profile"), "renamed\nproject\n")
    }

    // MARK: - 3.6 The model needs no helper

    func testEveryStoreOperationSucceedsWithNoHelperAndLeavesTheLiveFileAlone() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let helper = UnregisteredHelper()
        let model = fixture.model(writer: helper)
        let liveBefore = try fixture.live.state()

        XCTAssertEqual(model.createProfile(named: "fresh").store, .success(.wrote))
        XCTAssertEqual(model.createFragment(named: "extra").store, .success(.wrote))
        XCTAssertEqual(model.save(fragment: base, text: "127.0.0.1\trenamed.example\n", editing: other, previous: model.read(selection: .profile(other))).store, .success(.wrote))
        XCTAssertEqual(model.addLayer(project, to: other, previous: model.read(selection: .profile(other))).store, .success(.wrote))
        XCTAssertEqual(model.moveLayer(from: 1, to: 0, in: other, previous: model.read(selection: .profile(other))).store, .success(.wrote))
        XCTAssertEqual(model.removeLayer(at: 0, from: other, previous: model.read(selection: .profile(other))).store, .success(.wrote))
        XCTAssertEqual(model.duplicate(profile: work, as: "copy").store, .success(.wrote))
        XCTAssertEqual(model.duplicate(fragment: base, as: "copy").store, .success(.wrote))
        XCTAssertEqual(model.rename(profile: ProfileID("copy"), to: "renamed").store, .success(.wrote))
        XCTAssertEqual(model.rename(fragment: FragmentID("copy"), to: "renamed").store, .success(.wrote))
        XCTAssertEqual(model.delete(profile: ProfileID("fresh")).store, .success(.deleted))
        XCTAssertEqual(model.delete(fragment: FragmentID("extra")).store, .success(.deleted))

        XCTAssertEqual(helper.requests, 0, "authoring must not ask the helper for anything")
        XCTAssertEqual(try fixture.live.state(), liveBefore)
        XCTAssertEqual(model.read().profiles.map(\.rawValue), ["other", "renamed", "work"])
        XCTAssertEqual(model.read().fragments.map(\.rawValue), ["base", "project", "renamed"])
    }

    func testTheModelRefusesABadNameWithoutTouchingTheStore() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let outcome = model.createProfile(named: "../escape")

        XCTAssertEqual(outcome.store, .failure(.invalidName("../escape")))
        XCTAssertFalse(outcome.didChangeTheStore)
        XCTAssertEqual(model.read().profiles, [other, work])
    }

    func testTheModelCreatesRenamesAndDuplicatesNamesHoldingASpace() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let profile = ProfileID("Local Dev")
        XCTAssertEqual(model.createProfile(named: profile.rawValue).store, .success(.wrote))
        XCTAssertTrue(model.read().profiles.contains(profile))

        let fragment = FragmentID("Local Dev Base")
        XCTAssertEqual(model.createFragment(named: fragment.rawValue).store, .success(.wrote))
        XCTAssertTrue(model.read().fragments.contains(fragment))

        let renamed = ProfileID("Local Dev Two")
        XCTAssertEqual(model.rename(profile: profile, to: renamed.rawValue).store, .success(.wrote))
        XCTAssertEqual(model.read().profiles, [renamed, other, work])

        let copy = FragmentID("Local Dev Base Copy")
        XCTAssertEqual(model.duplicate(fragment: fragment, as: copy.rawValue).store, .success(.wrote))
        XCTAssertTrue(model.read().fragments.contains(copy))
    }

    // MARK: - 3.7 A fragment changed outside the application

    /// The store is read when it is asked: a cache answers only about bytes that
    /// came back identical, so a file another tool rewrote is read as it is now.
    func testAFragmentChangedByAnotherToolChangesTheNextRead() throws {
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let model = EditorModel(
            storeRoot: fixture.store.root,
            fileURL: fixture.live.url,
            writer: UnregisteredHelper(),
            cache: StoreCache()
        )

        let before = model.read(selection: .profile(work))
        XCTAssertEqual(before.entryCount(of: base), 1)
        XCTAssertEqual(before.layerRows.map(\.entryCount), [1, 1])
        XCTAssertEqual(before.entries.map(\.name), ["localhost", "alpha.example"])
        XCTAssertEqual(before.entryCount, 2)

        // Another tool adds a line to a fragment the selected profile stacks.
        try fixture.store.write(
            "127.0.0.1\tlocalhost alpha.example\n::1\tbeta.example\n",
            to: "fragments/base.hosts"
        )

        let after = model.read(selection: .profile(work))

        XCTAssertNotEqual(after, before, "the read sees the bytes another tool wrote")
        XCTAssertEqual(after.entryCount(of: base), 2, "the fragment's entry count follows the file")
        XCTAssertEqual(after.layerRows.map(\.entryCount), [2, 1], "so does the layer row's")
        XCTAssertEqual(after.entryCount, 3, "and so does the resolved view")
        XCTAssertEqual(after.entries.map(\.name), ["localhost", "beta.example", "alpha.example"])
        XCTAssertEqual(
            after.entries.first { $0.name == "alpha.example" }?.address,
            "10.0.0.9",
            "the later layer still wins the name both fragments hold"
        )

        // The bytes just read are the ones the next read is answered from.
        XCTAssertEqual(model.read(selection: .profile(work)), after)
    }

    // MARK: - 3.8 A refresh is an edit

    /// The store of `stackedFixture` with an `ads` fragment that only `other`
    /// stacks, so a refresh of it reaches no live profile.
    private func remoteFixture() throws -> (StoreFixture, RemoteSource) {
        let fixture = try StoreFixture(
            store: [
                ("127.0.0.1\tlocalhost alpha.example\n", "fragments/base.hosts"),
                ("10.0.0.9\talpha.example\n", "fragments/project.hosts"),
                ("0.0.0.0\tads.example.com\n", "fragments/ads.hosts"),
                ("base\nproject\n", "profiles/work.profile"),
                ("base\nads\n", "profiles/other.profile")
            ],
            live: "127.0.0.1\tlocalhost\n"
        )
        let source = RemoteSource(
            url: URL(string: "https://example.com/base.txt")!,
            interval: 86_400,
            lastAttempt: Date(timeIntervalSince1970: 1_759_000_000),
            lastSuccess: Date(timeIntervalSince1970: 1_759_000_000),
            etag: "\"v1\""
        )
        return (fixture, source)
    }

    func testARefreshOfAFragmentTheAppliedProfileStacksRewritesTheLiveBlock() async throws {
        let (fixture, source) = try remoteFixture()
        defer { fixture.remove() }
        let writer = LocalWriter(target: fixture.live.url)
        let model = fixture.model(writer: writer)
        try fixture.applyToLive(work)
        let before = model.read(selection: .profile(work))
        XCTAssertEqual(before.appliedProfiles, [work])

        let fetcher = StubFetcher(
            .succeeded(body: bytes("127.0.0.1\trefreshed.example\n"), etag: "\"v2\"", finalURL: source.url)
        )
        let outcome = await model.refresh(
            fragment: base, source: source, previous: before, fetcher: fetcher,
            at: Date(timeIntervalSince1970: 1_760_000_000)
        )

        XCTAssertEqual(outcome.store, .success(.wrote))
        XCTAssertEqual(outcome.apply, .applied(.replacedBlock(overwroteDrift: true)))
        XCTAssertEqual(writer.writes, 1)
        XCTAssertEqual(try fixture.text("fragments/base.hosts"), "127.0.0.1\trefreshed.example\n")
        XCTAssertEqual(outcome.refresh?.outcome, .wrote)
        XCTAssertTrue(outcome.description.contains("new text"), outcome.description)

        let live = try XCTUnwrap(ManagedBlock.locate(in: fixture.live.data))
        XCTAssertEqual(Data(fixture.live.data[live.range]), try fixture.rendered(work))
        XCTAssertEqual(text(try BlockSplice.strip(from: fixture.live.data)), "127.0.0.1\tlocalhost\n")
    }

    func testARefreshWhoseLiveBlockMovedReportsDriftAndLeavesTheFileAlone() async throws {
        let (fixture, source) = try remoteFixture()
        defer { fixture.remove() }
        let writer = LocalWriter(target: fixture.live.url)
        let model = fixture.model(writer: writer)
        try fixture.applyToLive(work)
        let before = model.read(selection: .profile(work))
        XCTAssertEqual(before.appliedProfiles, [work])

        // Another tool changes a line inside the block after the read.
        let changed = bytes(text(fixture.live.data).replacingOccurrences(of: "alpha.example", with: "moved.example"))
        try fixture.live.write(changed)

        let fetcher = StubFetcher(.succeeded(body: bytes("127.0.0.1\trefreshed.example\n"), finalURL: source.url))
        let outcome = await model.refresh(
            fragment: base, source: source, previous: before, fetcher: fetcher,
            at: Date(timeIntervalSince1970: 1_760_000_000)
        )

        XCTAssertEqual(outcome.apply, .refused(.driftNotOverwritten))
        XCTAssertEqual(writer.writes, 0)
        XCTAssertEqual(fixture.live.data, changed, "the live file is left as it is")
        XCTAssertEqual(
            try fixture.text("fragments/base.hosts"),
            "127.0.0.1\trefreshed.example\n",
            "the refreshed text is in the store regardless"
        )
        XCTAssertTrue(outcome.description.contains("drift"), outcome.description)
    }

    func testARefreshOfAFragmentNoAppliedProfileStacksLeavesTheLiveFileAlone() async throws {
        let (fixture, source) = try remoteFixture()
        defer { fixture.remove() }
        let writer = LocalWriter(target: fixture.live.url)
        let model = fixture.model(writer: writer)
        try fixture.applyToLive(work)
        let before = model.read(selection: .profile(work))
        let liveBefore = try fixture.live.state()
        XCTAssertEqual(before.appliedProfiles, [work])
        XCTAssertEqual(before.stacks(ads), [other], "only the profile that is not live stacks it")

        let fetcher = StubFetcher(.succeeded(body: bytes("0.0.0.0\tnew-ads.example.com\n"), finalURL: source.url))
        let outcome = await model.refresh(
            fragment: ads, source: source, previous: before, fetcher: fetcher,
            at: Date(timeIntervalSince1970: 1_760_000_000)
        )

        XCTAssertEqual(outcome.store, .success(.wrote))
        XCTAssertNil(outcome.apply, "no live profile stacks the refreshed fragment")
        XCTAssertEqual(writer.writes, 0)
        XCTAssertEqual(try fixture.live.state(), liveBefore, "the bytes and the modification time are untouched")
        XCTAssertEqual(try fixture.text("fragments/ads.hosts"), "0.0.0.0\tnew-ads.example.com\n")
    }

    func testARefreshWhoseApplyIsRefusedKeepsTheRefreshedTextAndReportsTheReason() async throws {
        let (fixture, source) = try remoteFixture()
        defer { fixture.remove() }
        let helper = UnregisteredHelper()
        let model = fixture.model(writer: helper)
        try fixture.applyToLive(work)
        let before = model.read(selection: .profile(work))
        let liveBefore = try fixture.live.state()

        let fetcher = StubFetcher(.succeeded(body: bytes("127.0.0.1\trefreshed.example\n"), finalURL: source.url))
        let outcome = await model.refresh(
            fragment: base, source: source, previous: before, fetcher: fetcher,
            at: Date(timeIntervalSince1970: 1_760_000_000)
        )

        XCTAssertEqual(outcome.store, .success(.wrote))
        XCTAssertEqual(outcome.apply, .refused(.privileged("the helper is not registered")))
        XCTAssertEqual(helper.requests, 1)
        XCTAssertEqual(try fixture.live.state(), liveBefore, "the live file is unchanged")
        XCTAssertEqual(try fixture.text("fragments/base.hosts"), "127.0.0.1\trefreshed.example\n")
        XCTAssertTrue(outcome.needsAttention)
        XCTAssertTrue(outcome.description.contains("not registered"), outcome.description)
    }

    func testARefreshSaysWhatItDidOnceRatherThanTwice() async throws {
        // A refresh's own answer covers the store, so the store's clause is not
        // repeated. Before this, the two ran together with nothing between them:
        // "the source is unchanged the store already held that text".
        let (fixture, source) = try remoteFixture()
        defer { fixture.remove() }
        let writer = LocalWriter(target: fixture.live.url)
        let model = fixture.model(writer: writer)
        try fixture.applyToLive(work)
        let before = model.read(selection: .profile(work))

        let unchanged = await model.refresh(
            fragment: base,
            source: source,
            previous: before,
            fetcher: StubFetcher(.notModified(etag: "\"v1\"", finalURL: source.url)),
            at: Date(timeIntervalSince1970: 1_760_000_000)
        )
        XCTAssertEqual(unchanged.description, "the source is unchanged")

        let refused = await model.refresh(
            fragment: base,
            source: source,
            previous: before,
            fetcher: StubFetcher(.refused("the server answered 503", finalURL: source.url)),
            at: Date(timeIntervalSince1970: 1_760_000_000)
        )
        XCTAssertEqual(
            refused.description,
            "the source was not refreshed: the server answered 503",
            "a failure carries no tail about the store"
        )

        let written = await model.refresh(
            fragment: base,
            source: source,
            previous: model.read(selection: .profile(work)),
            fetcher: StubFetcher(.succeeded(body: bytes("127.0.0.1\trefreshed.example\n"), finalURL: source.url)),
            at: Date(timeIntervalSince1970: 1_760_000_000)
        )
        XCTAssertEqual(
            written.description,
            "the source fetched new text applied: drift was overwritten",
            "the text and the apply, and no third clause repeating either"
        )
    }

    func testAnEditStillSaysWhatTheStoreDid() async throws {
        // The store's own clause is only dropped when a refresh describes it: an
        // ordinary edit has nothing else to say about the store.
        let fixture = try stackedFixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: LocalWriter(target: fixture.live.url))

        let saved = model.save(
            fragment: base,
            text: "127.0.0.1\tchanged.example\n",
            editing: nil,
            previous: model.read(selection: .profile(work))
        )
        XCTAssertEqual(saved.description, "the store holds the edit")

        let identical = model.save(
            fragment: base,
            text: "127.0.0.1\tchanged.example\n",
            editing: nil,
            previous: model.read(selection: .profile(work))
        )
        XCTAssertEqual(identical.description, "the store already held that text")

        let deleted = model.delete(fragment: project)
        XCTAssertEqual(deleted.description, "the name was deleted")
    }

    func testARefreshWithNoChangeWritesNothingAndReportsIt() async throws {
        let (fixture, source) = try remoteFixture()
        defer { fixture.remove() }
        let writer = LocalWriter(target: fixture.live.url)
        let model = fixture.model(writer: writer)
        try fixture.applyToLive(work)
        let before = model.read(selection: .profile(work))
        let liveBefore = try fixture.live.state()
        let fragmentBefore = try FileState(of: fixture.store.root.appendingPathComponent("fragments/base.hosts"))

        let fetcher = StubFetcher(.notModified(etag: "\"v1\"", finalURL: source.url))
        let outcome = await model.refresh(
            fragment: base, source: source, previous: before, fetcher: fetcher,
            at: Date(timeIntervalSince1970: 1_760_000_000)
        )

        XCTAssertEqual(outcome.refresh?.outcome, .unchanged)
        XCTAssertEqual(outcome.store, .success(.unchanged))
        XCTAssertNil(outcome.apply)
        XCTAssertEqual(writer.writes, 0)
        XCTAssertEqual(try fixture.live.state(), liveBefore)
        XCTAssertEqual(
            try FileState(of: fixture.store.root.appendingPathComponent("fragments/base.hosts")),
            fragmentBefore
        )
    }

    func testARefusedRefreshLeavesTheStoreAndTheLiveFileAlone() async throws {
        let (fixture, source) = try remoteFixture()
        defer { fixture.remove() }
        let writer = LocalWriter(target: fixture.live.url)
        let model = fixture.model(writer: writer)
        try fixture.applyToLive(work)
        let before = model.read(selection: .profile(work))
        let liveBefore = try fixture.live.state()
        let fragmentBefore = try FileState(of: fixture.store.root.appendingPathComponent("fragments/base.hosts"))

        let fetcher = StubFetcher(.succeeded(body: bytes("# hazmat:remove ads.example.com\n"), finalURL: source.url))
        let outcome = await model.refresh(
            fragment: base, source: source, previous: before, fetcher: fetcher,
            at: Date(timeIntervalSince1970: 1_760_000_000)
        )

        XCTAssertEqual(outcome.refresh?.wasRefused, true)
        XCTAssertEqual(writer.writes, 0)
        XCTAssertEqual(try fixture.live.state(), liveBefore)
        XCTAssertEqual(
            try FileState(of: fixture.store.root.appendingPathComponent("fragments/base.hosts")),
            fragmentBefore
        )
        XCTAssertTrue(outcome.needsAttention)
        XCTAssertTrue(outcome.description.contains("hazmat:"), outcome.description)
    }
}
