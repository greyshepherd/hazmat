import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

/// One reading serves the window and the menu: the presentation and the
/// activation come from one reading of the store and one read of the live
/// file, so they cannot disagree and the file is not read twice per refresh.
final class EditorReadingTests: XCTestCase {
    private let work = ProfileID("work")
    private let other = ProfileID("other")

    private func fixture() throws -> StoreFixture {
        try StoreFixture(
            store: [
                ("127.0.0.1\tlocalhost alpha.example\n", "fragments/base.hosts"),
                ("10.0.0.9\tproject.example\n", "fragments/project.hosts"),
                ("base\nproject\n", "profiles/work.profile"),
                ("base\n", "profiles/other.profile")
            ],
            live: "127.0.0.1\tlocalhost\n"
        )
    }

    private func liveHolding(_ profile: ProfileID, in fixture: StoreFixture) throws -> Data {
        let block = try ProfileCatalogue(root: fixture.store.root).renderedBlock(for: profile)
        return try BlockSplice.splice(block: block, into: fixture.shipped)
    }

    func testOneReadingReadsTheLiveFileOnceAndAnswersBoth() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let file = CountingFile(try liveHolding(other, in: fixture))
        let model = EditorModel(storeRoot: fixture.store.root, fileURL: fixture.live.url, writer: UnregisteredHelper(), liveFile: file)

        let reading = model.reading(selection: .profile(work), detail: false)

        XCTAssertEqual(file.reads, 1)
        XCTAssertEqual(reading.activation.activation?.state, .active([other]))
        XCTAssertEqual(reading.activation.profiles, [other, work])
        XCTAssertEqual(reading.presentation.appliedProfiles, [other])
        XCTAssertEqual(reading.presentation.selectedProfile, work)
        guard case .drifted(let digest) = reading.presentation.live else {
            return XCTFail("the selected profile is not the live one: \(reading.presentation.live)")
        }
        XCTAssertEqual(digest, try ProfileCatalogue(root: fixture.store.root).renderedDigest(for: other))
        XCTAssertEqual(reading.presentation.liveBlock, digest)
        XCTAssertEqual(reading.activation.activation?.liveBlock, digest, "the activation names the same block")
    }

    func testTheActivationAgreesWithThePresentationInEveryState() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let model = { (file: CountingFile) in
            EditorModel(storeRoot: fixture.store.root, fileURL: fixture.live.url, writer: UnregisteredHelper(), liveFile: file)
        }

        let off = model(CountingFile(fixture.shipped)).reading(selection: .profile(work))
        XCTAssertEqual(off.activation.activation?.state, .off)
        XCTAssertEqual(off.presentation.live, .absent)

        let applied = model(CountingFile(try liveHolding(work, in: fixture))).reading(selection: .profile(work))
        XCTAssertEqual(applied.activation.activation?.state, .active([work]))
        XCTAssertEqual(applied.presentation.live, .applied)
        XCTAssertTrue(applied.presentation.isApplied)

        let stranger = bytes("# >>> hazmat:managed v1 >>>\n10.1.2.3 stranger.example\n# <<< hazmat:managed v1 <<<\n")
        let drifted = model(CountingFile(try BlockSplice.splice(block: stranger, into: fixture.shipped))).reading(selection: .profile(work))
        XCTAssertEqual(drifted.activation.activation?.state, .drifted(ByteDigest(stranger)))
        XCTAssertEqual(drifted.presentation.live, .drifted(ByteDigest(stranger)))

        struct Unreadable: Error {}
        let unreadable = model(CountingFile(failing: Unreadable())).reading(selection: .profile(work))
        XCTAssertEqual(unreadable.activation.profiles, [other, work])
        XCTAssertNil(unreadable.activation.activation)
        guard case .unreadable = unreadable.presentation.live else {
            return XCTFail("expected an unreadable file, got \(unreadable.presentation.live)")
        }
    }

    func testAStoreWithNoProfilesIsAnEmptyStoreForTheMenu() throws {
        let fixture = try StoreFixture(store: [("127.0.0.1\tlocalhost\n", "fragments/base.hosts")], live: "127.0.0.1\tlocalhost\n")
        defer { fixture.remove() }
        let file = CountingFile(fixture.shipped)
        let model = EditorModel(storeRoot: fixture.store.root, fileURL: fixture.live.url, writer: UnregisteredHelper(), liveFile: file)

        let reading = model.reading()

        XCTAssertEqual(reading.activation, .emptyStore)
        XCTAssertEqual(reading.presentation.profiles, [])
    }
}
