import Foundation
import HazmatAppSupport
import HazmatCore
import XCTest
@testable import HazmatApp

/// The shell's refresh schedule and its on-demand refresh. Every exchange is
/// scripted, so nothing here reaches the network, and the clock is a value the
/// test moves.
private let start = Date(timeIntervalSince1970: 1_760_000_000)
private let url = URL(string: "https://example.com/base.txt")!
private let projectURL = URL(string: "https://example.com/project.txt")!
private let hour: TimeInterval = 3600
private let refreshed = "127.0.0.1\tlocalhost refreshed.example\n"
private let freshBody = Data(refreshed.utf8)

final class ShellSourceTests: XCTestCase {
    private func world() throws -> ShellWorld {
        try ShellWorld()
    }

    // MARK: - 3.3 The due check

    @MainActor
    func testTheDueCheckFetchesOncePerInterval() async throws {
        let world = try world()
        defer { world.remove() }
        let clock = TestClock(start)
        // A source that has never been fetched is due at once.
        try world.writeSource(world.base, url: url.absoluteString, interval: 6 * hour)
        let fetcher = ScriptedFetcher { _ in .succeeded(body: freshBody, etag: "\"v1\"", finalURL: url) }

        let model = world.model(fetcher: fetcher, clock: { clock.now })
        await settle { fetcher.count == 1 && !model.busy }
        XCTAssertEqual(fetcher.count, 1, "the launch check fetched the due source once")
        XCTAssertTrue(model.notice.text.contains("new text"), model.notice.text)
        XCTAssertEqual(try world.fragmentText(world.base), refreshed)

        // Inside the interval nothing more is exchanged, however often the check
        // runs.
        clock.advance(hour)
        model.refreshDueSources()
        model.refreshDueSources()
        model.refreshDueSources()
        XCTAssertEqual(fetcher.count, 1)

        // Once the interval has elapsed since the last contact it is fetched
        // again — once, not once per check.
        clock.advance(6 * hour)
        model.refreshDueSources()
        await settle { fetcher.count == 2 && !model.busy }
        XCTAssertEqual(fetcher.count, 2, "one exchange per interval")
        model.refreshDueSources()
        model.refreshDueSources()
        XCTAssertEqual(fetcher.count, 2)

        // And a third interval gives exactly one more.
        clock.advance(7 * hour)
        model.refreshDueSources()
        await settle { fetcher.count == 3 && !model.busy }
        XCTAssertEqual(fetcher.count, 3)
    }

    @MainActor
    func testASourceSetToManualIsNeverFetchedByTheSchedule() async throws {
        let world = try world()
        defer { world.remove() }
        let clock = TestClock(start)
        try world.writeSource(world.base, url: url.absoluteString, interval: RemoteInterval.manual)
        let fetcher = ScriptedFetcher(.succeeded(body: freshBody, finalURL: url))

        let model = world.model(fetcher: fetcher, clock: { clock.now })
        clock.advance(100 * hour)
        model.refreshDueSources()

        XCTAssertEqual(fetcher.count, 0)

        // It is still fetched when it is asked for.
        model.refreshSource(world.base)
        await settle { fetcher.count == 1 }
        XCTAssertEqual(fetcher.count, 1)
    }

    @MainActor
    func testASourceWhoseTextIsNotThereIsNotFetchedByTheSchedule() async throws {
        let world = try world()
        defer { world.remove() }
        let clock = TestClock(start)
        // A sidecar with no fragment: the store is inconsistent, or a first fetch
        // failed. The schedule leaves it alone rather than silently refilling it.
        try FileManager.default.removeItem(at: world.root.appendingPathComponent("fragments/base.hosts"))
        try world.writeSource(
            world.base,
            url: url.absoluteString,
            interval: 6 * hour,
            lastFailure: "the server answered 503"
        )
        XCTAssertFalse(world.hasFragment(world.base))
        let fetcher = ScriptedFetcher(.succeeded(body: freshBody, finalURL: url))

        let model = world.model(fetcher: fetcher, clock: { clock.now })
        clock.advance(100 * hour)
        model.refreshDueSources()

        XCTAssertEqual(fetcher.count, 0, "a source with no fragment is reported, not fetched")

        // It stays askable, which is how a first text is fetched and how a broken
        // source is recovered.
        model.refreshSource(world.base)
        await settle { fetcher.count == 1 && !model.busy }
        XCTAssertEqual(fetcher.count, 1)
        XCTAssertTrue(world.hasFragment(world.base))
        XCTAssertNil(try world.source(world.base).lastFailure)
    }

    @MainActor
    func testADueSourceAlreadyInFlightIsSkippedRatherThanQueuedTwice() async throws {
        let world = try world()
        defer { world.remove() }
        let clock = TestClock(start)
        try world.writeSource(world.base, url: url.absoluteString, interval: 6 * hour)
        let gate = Gate()
        let fetcher = ScriptedFetcher { _ in
            await gate.wait()
            return .succeeded(body: freshBody, finalURL: url)
        }

        let model = world.model(fetcher: fetcher, clock: { clock.now })
        await settle { fetcher.count == 1 }

        // The source is still due on disk while its exchange is out, so every
        // further check sees it. None of them queues a second exchange.
        model.refreshDueSources()
        model.refreshDueSources()
        model.refreshSource(world.base)
        XCTAssertEqual(fetcher.count, 1, "the source is in flight, so it is skipped")

        await gate.open()
        await settle { !model.busy }
        XCTAssertEqual(fetcher.count, 1)

        // The attempt was recorded, so the source is no longer due.
        XCTAssertEqual(try world.source(world.base).lastAttempt, start)
        model.refreshDueSources()
        XCTAssertEqual(fetcher.count, 1)
    }

    @MainActor
    func testTheWindowStaysReadableWhileAnExchangeIsInFlight() async throws {
        let world = try world()
        defer { world.remove() }
        let clock = TestClock(start)
        try world.writeSource(world.base, url: url.absoluteString, interval: 6 * hour)
        let gate = Gate()
        let fetcher = ScriptedFetcher { _ in
            await gate.wait()
            return .succeeded(body: freshBody, finalURL: url)
        }
        let reads = ReadCounter()
        let model = world.model(fetcher: fetcher, clock: { clock.now }, read: { session, selection, search, activation, _ in
            reads.bump()
            return (session.editor.read(selection: selection, search: search), nil)
        })
        await settle { fetcher.count == 1 }

        // The exchange is out, and the window still has its reading to render and
        // still lands a new one.
        XCTAssertEqual(model.editor.fragments.map(\.rawValue), ["base", "project"])
        let before = reads.count
        model.refresh()
        await settle { reads.count > before }
        XCTAssertGreaterThan(reads.count, before, "a read still lands while an exchange is in flight")

        await gate.open()
        await settle { !model.busy }
    }

    // MARK: - 3.4 Refresh on demand

    @MainActor
    func testRefreshingOnDemandFetchesASourceThatIsNotDue() async throws {
        let world = try world()
        defer { world.remove() }
        let clock = TestClock(start)
        // Refreshed a moment ago, so the schedule would leave it alone.
        try world.writeSource(
            world.base,
            url: url.absoluteString,
            interval: 6 * hour,
            lastAttempt: start.addingTimeInterval(-60),
            lastSuccess: start.addingTimeInterval(-60),
            etag: "\"v1\""
        )
        let fetcher = ScriptedFetcher(.succeeded(body: freshBody, etag: "\"v2\"", finalURL: url))

        let model = world.model(fetcher: fetcher, clock: { clock.now })
        model.refreshDueSources()
        XCTAssertEqual(fetcher.count, 0, "the source is not due")

        model.refreshSource(world.base)
        await settle { fetcher.count == 1 && !model.busy }
        XCTAssertEqual(fetcher.count, 1, "an asked-for refresh runs regardless of the interval")
        XCTAssertEqual(fetcher.requests.first?.etag, "\"v1\"")
        XCTAssertEqual(try world.fragmentText(world.base), refreshed)
    }

    @MainActor
    func testRefreshingOnDemandRunsForEverySourceInTheQueueOneAtATime() async throws {
        let world = try world()
        defer { world.remove() }
        let clock = TestClock(start)
        try world.writeSource(world.base, url: url.absoluteString, interval: RemoteInterval.manual)
        try world.writeSource(world.project, url: projectURL.absoluteString, interval: RemoteInterval.manual)
        let fetcher = ScriptedFetcher { _ in .succeeded(body: freshBody, finalURL: url) }

        let model = world.model(fetcher: fetcher, clock: { clock.now })
        model.refreshSource(world.project)
        model.refreshSource(world.base)

        await settle(within: 4) { fetcher.count == 2 && !model.busy }
        XCTAssertEqual(fetcher.count, 2)
        XCTAssertEqual(Set(fetcher.requests.map(\.url)), [url, projectURL])
    }

    @MainActor
    func testAddingASourceRecordsItAndAsksForItsFirstFetch() async throws {
        let world = try world()
        defer { world.remove() }
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher(.succeeded(body: freshBody, etag: "\"v1\"", finalURL: url))
        let model = world.model(fetcher: fetcher, clock: { clock.now })
        let ads = FragmentID("ads")

        let outcome = model.addSource(named: "ads", url: url.absoluteString, interval: 6 * hour)

        XCTAssertEqual(outcome.store, .success(.wrote))
        XCTAssertEqual(model.selection, .fragment(ads))
        await settle { fetcher.count == 1 && !model.busy }
        XCTAssertEqual(fetcher.count, 1, "the first fetch is asked for, not waited for")
        XCTAssertEqual(try world.source(ads).url, url)
        XCTAssertEqual(try world.source(ads).interval, 6 * hour)
        XCTAssertEqual(try world.fragmentText(ads), refreshed)
    }

    @MainActor
    func testAddingASourceRefusesAURLOrIntervalItCouldNotUseAndWritesNothing() async throws {
        let world = try world()
        defer { world.remove() }
        let fetcher = ScriptedFetcher(.succeeded(body: freshBody, finalURL: url))
        let model = world.model(fetcher: fetcher, clock: { TestClock(start).now })

        let wrongScheme = model.addSource(named: "ads", url: "http://example.com/ads.txt", interval: 6 * hour)
        XCTAssertTrue(wrongScheme.needsAttention)
        XCTAssertTrue(wrongScheme.problem?.contains("HTTPS") ?? false, wrongScheme.problem ?? "no problem")
        XCTAssertEqual(world.sourceIfAny(FragmentID("ads")), nil)

        let tooShort = model.addSource(named: "ads", url: url.absoluteString, interval: 60)
        XCTAssertTrue(tooShort.needsAttention)
        XCTAssertTrue(tooShort.problem?.contains("15 minutes") ?? false, tooShort.problem ?? "no problem")
        XCTAssertEqual(world.sourceIfAny(FragmentID("ads")), nil)

        let badName = model.addSource(named: "../escape", url: url.absoluteString, interval: 6 * hour)
        XCTAssertTrue(badName.needsAttention)
        XCTAssertEqual(world.sourceIfAny(FragmentID("../escape")), nil)

        XCTAssertEqual(fetcher.count, 0, "nothing was asked to refresh")
    }

    // MARK: - The window renders what the specs promise

    func testTheSidebarRowAndTheFragmentEditorPresentASourceAsTheSpecsSay() throws {
        let sidebar = try windowSource("SidebarView.swift")
        // The row is marked as fetched, names the domain it comes from, says when
        // it last refreshed and whether it is out of date, and offers the refresh
        // itself. The whole address stays reachable: the mark's tooltip carries
        // it, and the detail pane names it in full.
        XCTAssertTrue(sidebar.contains("row.isRemote"), sidebar)
        XCTAssertTrue(sidebar.contains("Image(systemName: \"globe\")"), sidebar)
        XCTAssertFalse(sidebar.contains("arrow.down.circle"), "an arrow read as an action, not as where the text comes from")
        XCTAssertTrue(sidebar.contains("origin.host ??"), sidebar)
        XCTAssertTrue(sidebar.contains("origin.state"), sidebar)
        XCTAssertTrue(sidebar.contains("model.refreshSource(fragment)"), sidebar)
        XCTAssertTrue(sidebar.contains(".help(row.origin?.url?.absoluteString"), sidebar)
        // The count is shown for a fetched fragment as well as a pasted one, and
        // only where there is text to count.
        XCTAssertTrue(sidebar.contains("row.entryCountPhrase"), sidebar)
        XCTAssertFalse(sidebar.contains("if !row.isRemote"), "the count is no longer kept from a source's row")

        let content = try windowSource("ContentPane.swift")
        // The text is read-only for a source, with the URL and the refresh action
        // beside it; an ordinary fragment is still editable and saveable.
        XCTAssertTrue(content.contains("isEditable: origin == nil"), content)
        XCTAssertTrue(content.contains("Fetched from"), content)
        XCTAssertTrue(content.contains("Button(\"Refresh Now\")"), content)
        XCTAssertTrue(content.contains("saveFragment(text: model.fragmentDraft)"), content)

        let shell = try windowSource("ShellModel.swift")
        XCTAssertTrue(shell.contains("guard !editor.isRemote(fragment) else"), shell)
    }

    private func windowSource(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/HazmatApp/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.isEmpty, "\(name) is missing")
        return text
    }

    // MARK: - 5.3 The add-source and edit-source sheets

    @MainActor
    func testTheSheetClosesOnAValidSourceAndStaysOpenOnARefusedOne() async throws {
        let world = try world()
        defer { world.remove() }
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher(.succeeded(body: freshBody, finalURL: url))
        let model = world.model(fetcher: fetcher, clock: { clock.now })
        let ads = FragmentID("ads")

        model.beginAddSource()
        XCTAssertNotNil(model.sourceSheet)
        XCTAssertFalse(try XCTUnwrap(model.sourceSheet).isUsable, "an empty sheet cannot be saved")

        // A URL that is not HTTPS is reported in the sheet, and nothing is
        // written.
        model.sourceSheetName = "ads"
        model.sourceSheetURL = "http://example.com/ads.txt"
        model.sourceSheetHours = 6
        XCTAssertFalse(try XCTUnwrap(model.sourceSheet).isUsable)
        XCTAssertTrue(try XCTUnwrap(model.sourceSheet).problem?.contains("HTTPS") ?? false)
        model.commitSourceSheet()
        XCTAssertNotNil(model.sourceSheet, "the sheet stays open")
        XCTAssertNil(world.sourceIfAny(ads))

        // So is an interval below the floor.
        model.sourceSheetURL = url.absoluteString
        model.sourceSheetHours = 0.1
        XCTAssertFalse(try XCTUnwrap(model.sourceSheet).isUsable)
        XCTAssertTrue(try XCTUnwrap(model.sourceSheet).problem?.contains("15 minutes") ?? false)
        model.commitSourceSheet()
        XCTAssertNotNil(model.sourceSheet)
        XCTAssertNil(world.sourceIfAny(ads))

        // A usable one is recorded and closes the sheet.
        model.sourceSheetHours = 6
        XCTAssertTrue(try XCTUnwrap(model.sourceSheet).isUsable)
        model.commitSourceSheet()

        XCTAssertNil(model.sourceSheet)
        XCTAssertEqual(try world.source(ads).interval, 6 * hour)
        await settle { fetcher.count == 1 && !model.busy }
        XCTAssertEqual(try world.fragmentText(ads), refreshed)
    }

    @MainActor
    func testTheEditSheetOpensOnASourceAndSavesItsURLAndInterval() async throws {
        let world = try world()
        defer { world.remove() }
        let clock = TestClock(start)
        try world.writeSource(
            world.base,
            url: url.absoluteString,
            interval: 6 * hour,
            lastAttempt: start,
            lastSuccess: start,
            etag: "\"v1\""
        )
        let model = world.model(fetcher: ScriptedFetcher(.refused("nothing was scripted")), clock: { clock.now })

        model.beginEditSource(world.base)
        let opened = try XCTUnwrap(model.sourceSheet)
        XCTAssertFalse(opened.asksForAName, "the name is the fragment's, and renaming it is a rename")
        XCTAssertEqual(opened.url, url.absoluteString)
        XCTAssertEqual(opened.hours, 6)
        XCTAssertTrue(opened.isUsable)

        model.sourceSheetURL = "https://mirror.example.com/base.txt"
        model.sourceSheetHours = 24
        model.commitSourceSheet()

        XCTAssertNil(model.sourceSheet)
        XCTAssertEqual(try world.source(world.base).url.absoluteString, "https://mirror.example.com/base.txt")
        XCTAssertEqual(try world.source(world.base).interval, 24 * hour)
        XCTAssertEqual(try world.source(world.base).etag, "\"v1\"", "the refresh state is kept")
    }

    @MainActor
    func testTheEditSheetRefusesANameThatIsNotASource() async throws {
        let world = try world()
        defer { world.remove() }
        let model = world.model(fetcher: ScriptedFetcher(.refused("nothing was scripted")), clock: { TestClock(start).now })

        model.beginEditSource(FragmentID("nothing-here"))

        XCTAssertNil(model.sourceSheet)
        XCTAssertTrue(model.notice.text.contains("not a source"), model.notice.text)
    }

    @MainActor
    func testEditingASourceKeepsItsStateAndChangesWhatItRecords() async throws {
        let world = try world()
        defer { world.remove() }
        let clock = TestClock(start)
        try world.writeSource(
            world.base,
            url: url.absoluteString,
            interval: 6 * hour,
            lastAttempt: start.addingTimeInterval(-60),
            lastSuccess: start.addingTimeInterval(-60),
            etag: "\"v1\""
        )
        let model = world.model(fetcher: ScriptedFetcher(.refused("nothing was scripted")), clock: { clock.now })

        let outcome = model.updateSource(world.base, url: "https://mirror.example.com/base.txt", interval: 24 * hour)

        XCTAssertEqual(outcome.store, .success(.wrote))
        let source = try world.source(world.base)
        XCTAssertEqual(source.url.absoluteString, "https://mirror.example.com/base.txt")
        XCTAssertEqual(source.interval, 24 * hour)
        XCTAssertEqual(source.etag, "\"v1\"", "the refresh state is unchanged")
        XCTAssertEqual(source.lastSuccess, start.addingTimeInterval(-60))

        let refused = model.updateSource(world.base, url: "http://mirror.example.com/base.txt", interval: 24 * hour)
        XCTAssertTrue(refused.needsAttention)
        XCTAssertEqual(try world.source(world.base).url, URL(string: "https://mirror.example.com/base.txt"))

        let absent = model.updateSource(FragmentID("nothing-here"), url: url.absoluteString, interval: 24 * hour)
        XCTAssertTrue(absent.needsAttention)
    }
}
