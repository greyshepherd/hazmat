import Foundation
import HazmatAppSupport
import HazmatCore
import XCTest
@testable import HazmatApp

/// A refresh reports itself the way an edit does, and takes the same one-writer
/// gate. Nothing here reaches the network.
final class ShellRefreshTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)
    private let url = URL(string: "https://example.com/base.txt")!
    private let hour: TimeInterval = 3600
    private let refreshed = "127.0.0.1\tlocalhost refreshed.example\n"
    private let edited = "127.0.0.1\tlocalhost edited.example\n"
    private var freshBody: Data { Data(refreshed.utf8) }

    /// `base` stacked by `work`, applied to the live file, and recorded as a
    /// source that was refreshed a moment ago — so the launch check leaves it
    /// alone and a test that wants it due moves the clock past the interval.
    @MainActor
    private func applied(
        _ world: ShellWorld,
        clock: TestClock,
        fetcher: any RemoteFetching,
        writer: PrivilegedWriter
    ) throws -> ShellModel {
        try world.writeSource(
            world.base,
            url: url.absoluteString,
            interval: 6 * hour,
            lastAttempt: start,
            lastSuccess: start,
            etag: "\"v1\""
        )
        let composition = try HostsComposer(store: DirectoryStore(root: world.root)).compose(profile: world.work)
        let block = BlockRenderer.render(composition)
        let shipped = Data("127.0.0.1\tlocalhost\n".utf8)
        try Data(try BlockSplice.splice(block: block, into: shipped)).write(to: world.liveURL)
        return world.model(writer: writer, fetcher: fetcher, clock: { clock.now })
    }

    // MARK: - 4.2 The one-writer gate

    @MainActor
    func testARefreshAskedForDuringAnEditIsLeftDueRatherThanRunConcurrently() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher(.succeeded(body: freshBody, etag: "\"v2\"", finalURL: url))
        let writer = CountingWriter(target: world.liveURL)
        let model = try applied(world, clock: clock, fetcher: fetcher, writer: writer)
        await settle { !model.busy && model.editor.isApplied }
        XCTAssertEqual(writer.writes, 0, "nothing has been written yet")
        // The edit acts on the ordinary fragment: `base` is the source, and a
        // remote fragment's text is read-only.
        model.selection = .fragment(world.project)
        model.selectionChanged()
        await settle { model.editor.selectedFragment == world.project && !model.busy }
        let baseBefore = try world.fragmentText(world.base)

        // The interval elapses, so the source is due.
        clock.advance(7 * hour)
        XCTAssertTrue(RemoteSchedule.isDue(try world.source(world.base), at: clock.now))

        // An edit takes the gate the moment it is asked for.
        model.saveFragment(text: edited)
        XCTAssertTrue(model.busy, "the edit holds the writer")

        // The refresh asked for at the same moment cannot have it, so it is left
        // due rather than run alongside.
        model.refreshSource(world.base)
        XCTAssertEqual(fetcher.count, 0, "no exchange is made while the edit holds the gate")

        await settle { !model.busy && writer.writes == 1 && model.editor.fragmentText == edited }
        XCTAssertEqual(writer.writes, 1, "exactly one apply, the edit's")
        XCTAssertEqual(try world.fragmentText(world.project), edited, "the store holds the edit")
        XCTAssertEqual(try world.fragmentText(world.base), baseBefore, "the source's text is untouched, so no fetch ran")

        // The source is still due: its sidecar was never touched.
        let source = try world.source(world.base)
        XCTAssertEqual(source.lastAttempt, start)
        XCTAssertEqual(source.etag, "\"v1\"")
        XCTAssertEqual(fetcher.count, 0)
        XCTAssertTrue(RemoteSchedule.isDue(source, at: clock.now), "the refresh is still due afterwards")
    }

    @MainActor
    func testARefreshThatTookTheGateRunsOnItsOwn() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher(.succeeded(body: freshBody, etag: "\"v2\"", finalURL: url))
        let writer = CountingWriter(target: world.liveURL)
        let model = try applied(world, clock: clock, fetcher: fetcher, writer: writer)
        await settle { !model.busy && model.editor.isApplied }

        model.refreshSource(world.base)
        await settle { !model.busy && writer.writes == 1 }

        XCTAssertEqual(fetcher.count, 1)
        XCTAssertEqual(writer.writes, 1, "the refresh re-applied the block")
        XCTAssertFalse(RemoteSchedule.isDue(try world.source(world.base), at: clock.now))
    }

    // MARK: - 4.3 The outcome reaches the window

    @MainActor
    func testASuccessfulRefreshReportsItselfAsAChangeAndTheWriteStateFollows() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher(.succeeded(body: freshBody, etag: "\"v2\"", finalURL: url))
        let writer = CountingWriter(target: world.liveURL)
        let model = try applied(world, clock: clock, fetcher: fetcher, writer: writer)
        await settle { !model.busy && model.editor.isApplied }
        let before = model.editor.entryLines.count

        model.refreshSource(world.base)
        await settle {
            !model.busy && model.editor.entryLines.contains(where: { $0.names.contains("refreshed.example") })
                && model.writeState == .inSync
        }

        XCTAssertEqual(model.notice, .success(model.notice.text))
        XCTAssertTrue(model.notice.text.contains("new text"), model.notice.text)
        XCTAssertTrue(model.notice.text.contains("applied"), model.notice.text)
        XCTAssertEqual(writer.writes, 1)

        // The resolved view and the write state follow the refresh exactly as
        // they follow an edit.
        let editor = model.editor
        XCTAssertTrue(editor.entries.contains { $0.name == "refreshed.example" })
        XCTAssertEqual(editor.entryLines.count, before, "the refreshed entry replaced the one it stood for")
        XCTAssertEqual(editor.entries.first { $0.name == "refreshed.example" }?.source.fragment, world.base)
        XCTAssertTrue(editor.isApplied)
        XCTAssertEqual(model.writeState, .inSync)
    }

    @MainActor
    func testAFailedRefreshReportsTheReasonAndLeavesTheWindowAsItWas() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher(.refused("the server answered 503", finalURL: url))
        let writer = CountingWriter(target: world.liveURL)
        let model = try applied(world, clock: clock, fetcher: fetcher, writer: writer)
        await settle { !model.busy && model.editor.isApplied }
        let fragmentBefore = try world.fragmentState(world.base)
        let liveBefore = try FileState(of: world.liveURL)
        let entriesBefore = model.editor.entries

        model.refreshSource(world.base)
        await settle { !model.busy && model.notice.text.contains("503") }

        XCTAssertEqual(model.notice, .failure(model.notice.text))
        XCTAssertTrue(model.notice.text.contains("503"), model.notice.text)
        XCTAssertTrue(model.notice.text.contains("not refreshed"), model.notice.text)
        XCTAssertEqual(writer.writes, 0)
        XCTAssertEqual(try world.fragmentState(world.base), fragmentBefore)
        XCTAssertEqual(try FileState(of: world.liveURL), liveBefore)
        XCTAssertEqual(model.editor.entries, entriesBefore)

        // The store still holds the reason, which the source's row reports.
        XCTAssertEqual(try world.source(world.base).lastFailure, "the server answered 503")
    }

    @MainActor
    func testARefusedBodyIsReportedWithItsReasonAndNothingIsWritten() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher(.succeeded(body: Data("# hazmat:remove ads.example.com\n".utf8), finalURL: url))
        let writer = CountingWriter(target: world.liveURL)
        let model = try applied(world, clock: clock, fetcher: fetcher, writer: writer)
        await settle { !model.busy && model.editor.isApplied }
        let fragmentBefore = try world.fragmentState(world.base)
        let liveBefore = try FileState(of: world.liveURL)

        model.refreshSource(world.base)
        await settle { !model.busy && model.notice.text.contains("hazmat:") }

        XCTAssertEqual(model.notice, .failure(model.notice.text))
        XCTAssertTrue(model.notice.text.contains("hazmat:"), model.notice.text)
        XCTAssertEqual(writer.writes, 0)
        XCTAssertEqual(try world.fragmentState(world.base), fragmentBefore)
        XCTAssertEqual(try FileState(of: world.liveURL), liveBefore)
    }

    @MainActor
    func testAnApplyRefusedByTheHelperIsReportedWithItsReasonAndTheTextStays() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher(.succeeded(body: freshBody, finalURL: url))
        let model = try applied(world, clock: clock, fetcher: fetcher, writer: SilentWriter())
        await settle { !model.busy && model.editor.isApplied }
        let liveBefore = try FileState(of: world.liveURL)

        model.refreshSource(world.base)
        await settle { !model.busy && model.notice.text.contains("not registered") }

        XCTAssertEqual(model.notice, .failure(model.notice.text))
        XCTAssertTrue(model.notice.text.contains("not registered"), model.notice.text)
        XCTAssertEqual(try world.fragmentText(world.base), refreshed, "the refreshed text is in the store")
        XCTAssertEqual(try FileState(of: world.liveURL), liveBefore, "the live file is unchanged")
        XCTAssertEqual(try world.source(world.base).lastSuccess, start, "the refresh still succeeded")
    }
}
