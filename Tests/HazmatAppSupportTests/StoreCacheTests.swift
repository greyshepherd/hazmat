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

    // MARK: - One derivation per key

    /// Two readings that derive the same answer at once — the window's read and
    /// the menu's, at launch — end up sharing one value, not holding one each: a
    /// composition of a hundred thousand names is not worth holding twice.
    func testDerivationsThatRaceForTheSameKeyShareTheStoredValue() {
        final class Derived: @unchecked Sendable {}
        let cache = StoreCache()
        let key = DerivationKey(profile: work, kind: .composition, generation: 1, layers: [base: 1])
        let arrived = DispatchSemaphore(value: 0)
        let proceed = DispatchSemaphore(value: 0)
        let results = Results()
        let group = DispatchGroup()

        // Both derive: neither finishes deriving until the other is deriving too.
        DispatchQueue.global().async {
            arrived.wait()
            arrived.wait()
            proceed.signal()
            proceed.signal()
        }
        for _ in 0..<2 {
            DispatchQueue.global().async(group: group) {
                let value: Derived = cache.derived(key) {
                    arrived.signal()
                    proceed.wait()
                    return Derived()
                }
                results.append(value)
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success, "both derivations finished")

        XCTAssertEqual(results.values.count, 2)
        XCTAssertTrue(results.values[0] === results.values[1], "both answer with the value the cache stored")
    }

    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [AnyObject] = []
        var values: [AnyObject] { lock.withLock { stored } }
        func append(_ value: AnyObject) { lock.withLock { stored.append(value) } }
    }

    // MARK: - Parses are held only while the window needs them

    /// A read the menu asks for — counts and renderings, no composition — parses
    /// nothing after a release while the bytes are unchanged: the renderings and
    /// the counts are kept, the parses are not. A read that composes parses
    /// again, once per layer.
    func testReleasingTheParsesKeepsTheCountsAndRenderings() throws {
        let store = try makeStore()
        defer { store.remove() }
        let cache = StoreCache()
        let tally = ParseTally()

        read(store, cache, tally)
        XCTAssertEqual(tally.fragments, 3)

        cache.releaseParses()

        let menuRead = StoreReading(layout: StoreLayout(root: store.root), cache: cache, parseFragment: { bytes, id in
            tally.countFragment()
            return FragmentParser.parse(bytes, as: id)
        }, parseProfile: { bytes, id in ProfileParser.parse(bytes, as: id) })
        for fragment in menuRead.fragments {
            _ = menuRead.fragment(fragment)?.entryCount
        }
        for profile in menuRead.profiles {
            _ = try menuRead.rendering(of: profile)
        }
        XCTAssertEqual(tally.fragments, 3, "counts and renderings are answered without a parse")
        XCTAssertEqual(menuRead.fragment(base)?.entryCount, 1)

        read(store, cache, tally)
        XCTAssertEqual(tally.fragments, 6, "composing again parses each stacked fragment once")
        read(store, cache, tally)
        XCTAssertEqual(tally.fragments, 6, "and holds them until the next release")
    }

    /// A fragment no profile stacks is parsed once for its count and not held;
    /// stacking it parses it once more, for composing.
    func testAFragmentNothingStacksIsCountedWithoutHoldingItsParse() throws {
        let store = try makeStore()
        defer { store.remove() }
        try store.write("0.0.0.0\torphan.example\n", to: "fragments/orphan.hosts")
        let cache = StoreCache()
        let tally = ParseTally()

        read(store, cache, tally)
        XCTAssertEqual(tally.fragments, 4, "counting the orphan is one parse")
        read(store, cache, tally)
        XCTAssertEqual(tally.fragments, 4, "the count is reused")

        try store.write("base\nads\norphan\n", to: "profiles/focus.profile")
        read(store, cache, tally)
        XCTAssertEqual(tally.fragments, 5, "stacked, it is parsed for composing")
        read(store, cache, tally)
        XCTAssertEqual(tally.fragments, 5, "and the parse is held")
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
        XCTAssertEqual(read(store, cache, tally).fragment(base)?.entryCount, 2)

        try store.write(oneEntry, to: "fragments/base.hosts")
        try FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: url.path)

        let after = read(store, cache, tally)

        XCTAssertEqual(after.fragment(base)?.entryCount, 1, "the new bytes are what was read")
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
