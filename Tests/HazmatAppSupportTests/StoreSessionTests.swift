import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

/// Re-pointing the store moves every read with it, and leaves the previous
/// location's files exactly as they were.
final class StoreSessionTests: XCTestCase {
    private let work = ProfileID("work")

    private func twoStores() throws -> (first: TemporaryStore, second: TemporaryStore) {
        let first = try TemporaryStore()
        try first.write("127.0.0.1\tlocalhost\n", to: "fragments/base.hosts")
        try first.write("base\n", to: "profiles/work.profile")

        let second = try TemporaryStore()
        try second.write("0.0.0.0\tads.example\n", to: "fragments/ads.hosts")
        try second.write("ads\n", to: "profiles/focus.profile")
        try second.write("ads\n", to: "profiles/quiet.profile")
        return (first, second)
    }

    func testRepointingListsTheNewLocationsContentsInsteadOfMerging() throws {
        let (first, second) = try twoStores()
        defer { first.remove(); second.remove() }
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let session = StoreSession(root: first.root, fileURL: live.url, writer: UnregisteredHelper())

        XCTAssertEqual(session.catalogue.profiles().map(\.rawValue), ["work"])

        let moved = session.repointed(to: second.root)

        XCTAssertEqual(moved.root, second.root)
        XCTAssertEqual(moved.catalogue.profiles().map(\.rawValue), ["focus", "quiet"])
        XCTAssertEqual(moved.editor.read().fragments.map(\.rawValue), ["ads"])
        XCTAssertEqual(
            moved.editor.read().profiles.map(\.rawValue),
            ["focus", "quiet"],
            "the new location's profiles, not the old ones"
        )
        XCTAssertEqual(moved.layout.root, second.root)
        XCTAssertEqual(moved.applier.file.url, live.url, "the live file moves with the store")
        XCTAssertEqual(moved.liveFile.url, live.url)
    }

    func testSwitchingBackLeavesThePreviousDirectorysFilesUntouched() throws {
        let (first, second) = try twoStores()
        defer { first.remove(); second.remove() }
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let session = StoreSession(root: first.root, fileURL: live.url, writer: UnregisteredHelper())
        let firstText = try first.text("profiles/work.profile")
        let secondText = try second.text("profiles/focus.profile")

        let moved = session.repointed(to: second.root)
        XCTAssertEqual(try second.text("fragments/ads.hosts"), "0.0.0.0\tads.example\n")

        let back = moved.repointed(to: first.root)

        XCTAssertEqual(back.catalogue.profiles().map(\.rawValue), ["work"])
        XCTAssertEqual(try first.text("profiles/work.profile"), firstText)
        XCTAssertEqual(try second.text("profiles/focus.profile"), secondText)
        XCTAssertEqual(back.editor.read(selection: .profile(work)).layers, [FragmentID("base")])
    }

    func testTheRepointedSessionKeepsTheWriterItWasGiven() throws {
        let (first, second) = try twoStores()
        defer { first.remove(); second.remove() }
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let writer = UnregisteredHelper()
        let session = StoreSession(root: first.root, fileURL: live.url, writer: writer)

        let moved = session.repointed(to: second.root)

        XCTAssertEqual(moved.editor.createProfile(named: "fresh").store, .success(.wrote))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.root.appendingPathComponent("profiles/fresh.profile").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.root.appendingPathComponent("profiles/fresh.profile").path))
    }
}
