import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport
@testable import HazmatCore

/// Counts the parses a reading made, so "the bytes were not parsed again" is
/// something the suite can show.
private final class ParseTally: @unchecked Sendable {
    private let lock = NSLock()
    private var fragmentCount = 0
    private var profileCount = 0

    var fragments: Int { lock.withLock { fragmentCount } }
    var profiles: Int { lock.withLock { profileCount } }

    func countFragment() { lock.withLock { fragmentCount += 1 } }
    func countProfile() { lock.withLock { profileCount += 1 } }
}

/// The cache is consulted about the bytes a read brought back, never about file
/// metadata, so a rewrite that keeps a file's size and second is still seen.
final class StoreCacheTests: XCTestCase {
    private let base = FragmentID("base")
    private let ads = FragmentID("ads")
    private let project = FragmentID("project")
    private let work = ProfileID("work")
    private let focus = ProfileID("focus")

    private func makeStore() throws -> TemporaryStore {
        let store = try TemporaryStore()
        try store.write("127.0.0.1\tlocalhost alpha.example\n", to: "fragments/base.hosts")
        try store.write("0.0.0.0\tads.example\n", to: "fragments/ads.hosts")
        try store.write("10.0.0.9\tproject.example\n", to: "fragments/project.hosts")
        try store.write("base\nproject\n", to: "profiles/work.profile")
        try store.write("base\nads\n", to: "profiles/focus.profile")
        return store
    }

    /// Reads the store, composes and renders every profile, and hands the
    /// reading back: what `EditorModel.read` and the menu's derivation do
    /// together.
    @discardableResult
    private func read(_ store: TemporaryStore, _ cache: StoreCache, _ tally: ParseTally) -> StoreReading {
        let reading = StoreReading(
            layout: StoreLayout(root: store.root),
            cache: cache,
            parseFragment: { bytes, id in
                tally.countFragment()
                return FragmentParser.parse(bytes, as: id)
            },
            parseProfile: { bytes, id in
                tally.countProfile()
                return ProfileParser.parse(bytes, as: id)
            }
        )
        for profile in reading.profiles {
            _ = try? reading.composition(of: profile)
            _ = try? reading.rendering(of: profile)
        }
        return reading
    }

    // MARK: - The same bytes

    func testTheSameBytesAreNotParsedAgain() throws {
        let store = try makeStore()
        defer { store.remove() }
        let cache = StoreCache()
        let tally = ParseTally()

        read(store, cache, tally)
        XCTAssertEqual(tally.fragments, 3)
        XCTAssertEqual(tally.profiles, 2)

        read(store, cache, tally)

        XCTAssertEqual(tally.fragments, 3, "the second read parsed nothing again")
        XCTAssertEqual(tally.profiles, 2)
    }

    func testARewriteOfTheSameLengthInTheSameSecondIsParsedAgain() throws {
        let store = try TemporaryStore()
        defer { store.remove() }
        let first = "127.0.0.1\ta.example\n"
        let second = "127.0.0.1\tb.example\n"
        let comment = "# " + String(repeating: "c", count: second.utf8.count - 3) + "\n"
        let twoEntries = first + second
        let oneEntry = first + comment
        XCTAssertEqual(twoEntries.utf8.count, oneEntry.utf8.count, "the fixture is a same-length rewrite")

        // Written with the same modification date, so a cache keyed on metadata
        // would answer with the bytes that are no longer there.
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let url = StoreLayout(root: store.root).fragmentURL(base)
        try store.write(twoEntries, to: "fragments/base.hosts")
        try FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: url.path)

        let cache = StoreCache()
        let tally = ParseTally()
        XCTAssertEqual(read(store, cache, tally).fragment(base)?.outcome.fragment.entries.count, 2)

        try store.write(oneEntry, to: "fragments/base.hosts")
        try FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: url.path)

        let after = read(store, cache, tally)

        XCTAssertEqual(after.fragment(base)?.outcome.fragment.entries.count, 1, "the new bytes are what was read")
        XCTAssertEqual(tally.fragments, 2, "a same-length rewrite in the same second is parsed again")
    }

    // MARK: - What a change invalidates

    func testAChangedFragmentInvalidatesEveryProfileStackingItAndNoOther() throws {
        let store = try makeStore()
        defer { store.remove() }
        let cache = StoreCache()
        let tally = ParseTally()

        read(store, cache, tally)
        let before = cache.derivationKeys

        try store.write("0.0.0.0\tads.example telemetry.example\n", to: "fragments/ads.hosts")
        read(store, cache, tally)

        let after = cache.derivationKeys
        XCTAssertNotEqual(
            after.filter { $0.profile == focus },
            before.filter { $0.profile == focus },
            "'focus' stacks the changed fragment, so it is derived again"
        )
        XCTAssertEqual(
            after.filter { $0.profile == work },
            before.filter { $0.profile == work },
            "'work' does not stack it, so its derivations stand"
        )
    }

    func testAChangedProfileInvalidatesOnlyItself() throws {
        let store = try makeStore()
        defer { store.remove() }
        let cache = StoreCache()
        let tally = ParseTally()

        read(store, cache, tally)
        let before = cache.derivationKeys

        try store.write("base\nproject\nads\n", to: "profiles/work.profile")
        read(store, cache, tally)

        let after = cache.derivationKeys
        XCTAssertNotEqual(after.filter { $0.profile == work }, before.filter { $0.profile == work })
        XCTAssertEqual(after.filter { $0.profile == focus }, before.filter { $0.profile == focus })
    }

    // MARK: - A file the store no longer lists

    func testAFileRemovedFromTheListingIsEvicted() throws {
        let store = try makeStore()
        defer { store.remove() }
        let cache = StoreCache()
        let tally = ParseTally()
        let layout = StoreLayout(root: store.root)
        let adsURL = layout.fragmentURL(ads)

        read(store, cache, tally)
        XCTAssertEqual(cache.heldFiles.count, 5)
        XCTAssertTrue(cache.heldFiles.contains(adsURL))

        try FileManager.default.removeItem(at: adsURL)
        read(store, cache, tally)

        XCTAssertFalse(cache.heldFiles.contains(adsURL), "a file the store no longer lists is evicted")
        XCTAssertEqual(cache.heldFiles.count, 4, "the files it still lists are still held")

        // Back with the same bytes, and parsed again rather than answered from a
        // cache entry that should be gone.
        try store.write("0.0.0.0\tads.example\n", to: "fragments/ads.hosts")
        let parsed = tally.fragments
        read(store, cache, tally)

        XCTAssertEqual(tally.fragments, parsed + 1, "the evicted file is parsed again")
    }
}
