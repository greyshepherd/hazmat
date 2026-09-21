import Foundation
import HazmatAppSupport
import HazmatCore
import XCTest
@testable import HazmatApp

/// The whole path, through the shell: add a source, fetch it, stack it in a
/// profile, apply that profile, refresh the source, and see the store and the
/// live file agree with the specs. Every exchange is scripted here, so nothing
/// reaches the network, and the live file is a temporary file beside the store.
private let start = Date(timeIntervalSince1970: 1_760_000_000)
private let url = URL(string: "https://example.com/feeds.txt")!
private let hour: TimeInterval = 3600
private let feeds = FragmentID("feeds")
private let firstBody = "0.0.0.0\tads.example.com\n"
private let secondBody = "0.0.0.0\tads.example.com tracker.example.com\n"
private let thirdBody = "0.0.0.0\tnewword.example.com\n"

final class RemoteEndToEndTests: XCTestCase {

    // MARK: - 6.1 The happy path

    @MainActor
    func testAddFetchStackApplyRefreshReachesBothFiles() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        XCTAssertTrue(
            world.liveURL.path.hasPrefix(FileManager.default.temporaryDirectory.path),
            "the live file is a temporary file, not /etc/hosts"
        )
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher { exchange in
            exchange == 1
                ? .succeeded(body: Data(firstBody.utf8), etag: "\"v1\"", finalURL: url)
                : .succeeded(body: Data(secondBody.utf8), etag: "\"v2\"", finalURL: url)
        }
        let writer = CountingWriter(target: world.liveURL)
        let model = world.model(writer: writer, fetcher: fetcher, clock: { clock.now }, approves: true)

        // 1. A source is created and fetched. No network is involved: the only
        // fetcher in this test is the script above.
        model.beginAddSource()
        model.sourceSheetName = "feeds"
        model.sourceSheetURL = url.absoluteString
        model.sourceSheetHours = 6
        model.commitSourceSheet()
        await settle { fetcher.count == 1 && !model.busy && world.hasFragment(feeds) }
        XCTAssertEqual(try world.fragmentText(feeds), firstBody)
        XCTAssertEqual(try world.source(feeds).url, url)

        // 2. The fetched fragment is stacked in the work profile like any other.
        model.selection = .profile(world.work)
        model.selectionChanged()
        await settle { model.editor.selectedProfile == world.work && !model.busy }
        model.addLayer(feeds)
        await settle { !model.busy && model.editor.layers.contains(feeds) }
        XCTAssertEqual(model.editor.layers, [world.base, world.project, feeds])

        // 3. The profile is applied, so its block is the live one.
        model.requestApply()
        model.confirm()
        await settle { !model.busy && writer.writes == 1 }
        let appliedBlock = try world.rendered(world.work)
        XCTAssertEqual(model.editor.liveBlock, ByteDigest(appliedBlock))
        XCTAssertTrue(model.editor.isApplied)
        let shipped = try BlockSplice.strip(from: Data(contentsOf: world.liveURL))
        XCTAssertEqual(shipped, Data("127.0.0.1\tlocalhost\n".utf8))

        // 4. The source is refreshed with changed text.
        model.refreshSource(feeds)
        await settle { !model.busy && writer.writes == 2 }

        // The store holds the newly fetched text, and the source's state says so.
        XCTAssertEqual(try world.fragmentText(feeds), secondBody)
        let source = try world.source(feeds)
        XCTAssertEqual(source.lastSuccess, start)
        XCTAssertEqual(source.etag, "\"v2\"")
        XCTAssertNil(source.lastFailure)

        // The live file holds the block the profile renders from the new text.
        let live = try Data(contentsOf: world.liveURL)
        let located = try XCTUnwrap(ManagedBlock.locate(in: live))
        let rendered = try world.rendered(world.work)
        XCTAssertEqual(Data(live[located.range]), rendered)
        XCTAssertEqual(try BlockSplice.strip(from: live), Data("127.0.0.1\tlocalhost\n".utf8))
        XCTAssertTrue(String(decoding: rendered, as: UTF8.self).contains("tracker.example.com"))

        // And the window agrees with both.
        XCTAssertTrue(model.editor.isApplied)
        XCTAssertEqual(model.writeState, .inSync)
        XCTAssertTrue(model.notice.text.contains("new text"), model.notice.text)
        XCTAssertEqual(model.notice, .success(model.notice.text), "a refresh that landed is a change, not a complaint")
    }

    // MARK: - 6.2 The failure path

    /// `base` recorded as a source, `work` applied, and the live file holding its
    /// block — so a refresh has somewhere to reach.
    @MainActor
    private func applied(_ world: ShellWorld, writer: PrivilegedWriter, fetcher: any RemoteFetching, clock: TestClock) throws -> ShellModel {
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
        try Data(try BlockSplice.splice(block: block, into: Data("127.0.0.1\tlocalhost\n".utf8))).write(to: world.liveURL)
        return world.model(writer: writer, fetcher: fetcher, clock: { clock.now })
    }

    @MainActor
    func testARefusedExchangeLeavesBothFilesExactlyAsTheyWere() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher(.refused("the exchange timed out", finalURL: url))
        let writer = CountingWriter(target: world.liveURL)
        let model = try applied(world, writer: writer, fetcher: fetcher, clock: clock)
        await settle { !model.busy && model.editor.isApplied }
        let fragmentBefore = try world.fragmentState(world.base)
        let liveBefore = try FileState(of: world.liveURL)

        model.refreshSource(world.base)
        await settle { !model.busy && model.notice.text.contains("timed out") }

        XCTAssertEqual(try world.fragmentState(world.base), fragmentBefore, "the store's bytes and modification time are untouched")
        XCTAssertEqual(try FileState(of: world.liveURL), liveBefore, "the live file's bytes and modification time are untouched")
        XCTAssertEqual(writer.writes, 0)
        XCTAssertEqual(model.notice, .failure(model.notice.text))
        XCTAssertTrue(model.notice.text.contains("the source was not refreshed"), model.notice.text)
        XCTAssertEqual(try world.source(world.base).lastFailure, "the exchange timed out")
        XCTAssertEqual(try world.source(world.base).lastSuccess, start, "the previous success stands")
    }

    @MainActor
    func testARefusedBodyLeavesBothFilesExactlyAsTheyWere() async throws {
        for (label, body) in [
            ("a directive", Data("# hazmat:remove ads.example.com\n".utf8)),
            ("not UTF-8", Data([0xFF, 0xFE, 0x0A])),
            ("over the bound", Data(repeating: UInt8(ascii: "a"), count: FetchBounds.bodySizeBound + 1))
        ] {
            let world = try ShellWorld()
            defer { world.remove() }
            let clock = TestClock(start)
            let fetcher = ScriptedFetcher(.succeeded(body: body, finalURL: url))
            let writer = CountingWriter(target: world.liveURL)
            let model = try applied(world, writer: writer, fetcher: fetcher, clock: clock)
            await settle { !model.busy && model.editor.isApplied }
            let fragmentBefore = try world.fragmentState(world.base)
            let liveBefore = try FileState(of: world.liveURL)

            model.refreshSource(world.base)
            await settle { !model.busy && !model.notice.isEmpty }

            XCTAssertEqual(try world.fragmentState(world.base), fragmentBefore, label)
            XCTAssertEqual(try FileState(of: world.liveURL), liveBefore, label)
            XCTAssertEqual(writer.writes, 0, label)
            XCTAssertEqual(model.notice, .failure(model.notice.text), label)
            XCTAssertTrue(model.notice.text.contains("the source was not refreshed"), model.notice.text)
            XCTAssertNotNil(try world.source(world.base).lastFailure, label)
            XCTAssertEqual(try world.source(world.base).lastSuccess, start, label)
            // The refused body is not stored anywhere in the store.
            XCTAssertFalse(
                (try world.storeEntries()).contains { $0.contains("hazmat-tests") },
                "no temporary file is left behind"
            )
        }
    }

    @MainActor
    func testAnApplyRefusedByTheHelperKeepsTheTextAndTheLiveFile() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher(.succeeded(body: Data(thirdBody.utf8), etag: "\"v2\"", finalURL: url))
        let model = try applied(world, writer: SilentWriter(), fetcher: fetcher, clock: clock)
        await settle { !model.busy && model.editor.isApplied }
        let liveBefore = try FileState(of: world.liveURL)

        model.refreshSource(world.base)
        await settle { !model.busy && model.notice.text.contains("not registered") }

        XCTAssertEqual(try world.fragmentText(world.base), thirdBody, "the refreshed text is in the store")
        XCTAssertEqual(try FileState(of: world.liveURL), liveBefore, "the live file's bytes and modification time are untouched")
        XCTAssertEqual(model.notice, .failure(model.notice.text))
        XCTAssertTrue(model.notice.text.contains("the privileged side refused"), model.notice.text)
        XCTAssertEqual(try world.source(world.base).lastSuccess, start, "the fetch itself succeeded")
        XCTAssertNil(try world.source(world.base).lastFailure)
        XCTAssertFalse(model.editor.isApplied, "the live file no longer holds the block the profile renders")
    }
}
