import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

/// An apply keeps the block it replaced, so the change can be undone for the
/// session; a revert is refused once the live block moved on.
final class RevertTests: XCTestCase {
    private let base = FragmentID("base")
    private let work = ProfileID("work")

    private func fixture() throws -> StoreFixture {
        try StoreFixture(
            store: [
                ("127.0.0.1\tlocalhost\n", "fragments/base.hosts"),
                ("127.0.0.1\tlocalhost\n10.0.0.9\talpha.example\n", "fragments/full.hosts"),
                ("base\n", "profiles/work.profile"),
                ("full\n", "profiles/full.profile")
            ],
            live: "127.0.0.1\tlocalhost\n"
        )
    }

    // MARK: - Reverting a replacement

    func testRevertingRestoresTheBlockTheApplyReplaced() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let writer = LocalWriter(target: fixture.live.url)
        let model = fixture.model(writer: writer)
        let full = ProfileID("full")
        // A first apply installs a block; a second apply replaces it, and the
        // block it replaced is the one to restore.
        let installed = model.apply(work, replacing: .onlyIfAbsent)
        XCTAssertTrue(installed.outcome.isApplied)
        let installedBlock = try fixture.rendered(work)

        let replaced = model.apply(full, replacing: .block(ByteDigest(installedBlock)))
        XCTAssertTrue(replaced.outcome.isApplied)
        let change = try XCTUnwrap(replaced.change)
        XCTAssertEqual(change.replaced, installedBlock)
        XCTAssertFalse(change.wasAnInstall)
        XCTAssertEqual(writer.writes, 2)

        let outcome = model.revert(change)

        XCTAssertEqual(outcome, .applied(.replacedBlock(overwroteDrift: true)))
        XCTAssertEqual(try BlockSplice.strip(from: fixture.live.data), fixture.shipped)
        XCTAssertEqual(try fixture.rendered(work), installedBlock)
        let located = try XCTUnwrap(ManagedBlock.locate(in: fixture.live.data))
        XCTAssertEqual(Data(fixture.live.data[located.range]), installedBlock)
    }

    func testRevertingAnInstallRemovesTheBlockAndRestoresTheBytes() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let writer = LocalWriter(target: fixture.live.url)
        let model = fixture.model(writer: writer)
        let before = fixture.shipped

        let applied = model.apply(work, replacing: .onlyIfAbsent)
        let change = try XCTUnwrap(applied.change)
        XCTAssertTrue(change.wasAnInstall)
        XCTAssertNotEqual(fixture.live.data, before)

        let outcome = model.revert(change)

        XCTAssertEqual(outcome, .applied(.removedBlock))
        XCTAssertEqual(fixture.live.data, before, "the file holds the bytes it held before the apply")
        XCTAssertEqual(writer.removals, 1)
    }

    func testARevertAfterAnOutsideEditIsRefusedAndTheFileIsUnchanged() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let writer = LocalWriter(target: fixture.live.url)
        let model = fixture.model(writer: writer)
        _ = model.apply(work, replacing: .onlyIfAbsent)
        let applied = model.apply(
            ProfileID("full"),
            replacing: .block(ByteDigest(try fixture.rendered(work)))
        )
        let change = try XCTUnwrap(applied.change)

        // Another tool edits inside the block.
        let edited = bytes(text(fixture.live.data).replacingOccurrences(of: "alpha.example", with: "moved.example"))
        try fixture.live.write(edited)

        let outcome = model.revert(change)

        XCTAssertEqual(outcome, .refused(.driftNotOverwritten))
        XCTAssertTrue(outcome.description.contains("drift"), outcome.description)
        XCTAssertEqual(fixture.live.data, edited)
    }

    func testARevertWithNoApplyThisSessionIsNotOffered() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let model = fixture.model(writer: UnregisteredHelper())

        let (outcome, change) = model.apply(work, replacing: .block(ByteDigest(bytes("a different block"))))

        XCTAssertEqual(change, nil, "an apply that wrote nothing records nothing")
        XCTAssertFalse(outcome.isApplied)
    }

    func testARevertNeedsTheSameGuaranteesAsAnApply() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let helper = UnregisteredHelper()
        let model = fixture.model(writer: helper)
        let change = ApplyRecord(profile: work, block: ByteDigest(try fixture.rendered(work)), replaced: fixture.shipped)

        // The recorded block is not the live one, and the helper refuses anyway.
        let outcome = model.revert(change)

        XCTAssertEqual(outcome, .refused(.driftNotOverwritten))
        XCTAssertEqual(fixture.live.data, fixture.shipped, "the file is untouched")
    }

    func testRevertingARecordedInstallRemovesTheBlockOnlyWhenTheLiveBlockIsTheOneItWrote() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let writer = LocalWriter(target: fixture.live.url)
        let model = fixture.model(writer: writer)
        let record = ApplyRecord(profile: work, block: ByteDigest(try fixture.rendered(work)), replaced: nil)

        try fixture.live.write(try BlockSplice.splice(block: try fixture.rendered(work), into: fixture.shipped))
        let outcome = model.revert(record)

        XCTAssertEqual(outcome, .applied(.removedBlock))
        XCTAssertEqual(fixture.live.data, fixture.shipped)
    }
}
