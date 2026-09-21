import Foundation
import XCTest
@testable import HazmatCore

/// Counts the parses a reading made, so "one parse per fragment" is something the
/// suite can show rather than something the reading promises.
private final class ParseTally: @unchecked Sendable {
    private let lock = NSLock()
    private var fragmentCount = 0
    private var profileCount = 0

    var fragments: Int { lock.withLock { fragmentCount } }
    var profiles: Int { lock.withLock { profileCount } }

    func countFragment() { lock.withLock { fragmentCount += 1 } }
    func countProfile() { lock.withLock { profileCount += 1 } }
}

/// A throwaway store directory a test writes fragments and profiles into.
private final class TempStore {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hazmat-reading-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func write(_ contents: String, to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

final class StoreReadingTests: XCTestCase {
    private let base = FragmentID("base")
    private let ads = FragmentID("ads")
    private let work = ProfileID("work")
    private let focus = ProfileID("focus")

    private func store() throws -> TempStore {
        let store = try TempStore()
        try store.write(
            "127.0.0.1\tlocalhost alpha.example\n::1\tapi.internal\n",
            to: "fragments/base.hosts"
        )
        try store.write("0.0.0.0\tads.example telemetry.example\n", to: "fragments/ads.hosts")
        try store.write("base\n", to: "profiles/work.profile")
        try store.write("base\nads\n", to: "profiles/focus.profile")
        return store
    }

    private func reading(of store: TempStore, tally: ParseTally) -> StoreReading {
        StoreReading(
            layout: StoreLayout(root: store.root),
            parseFragment: { bytes, id in
                tally.countFragment()
                return FragmentParser.parse(bytes, as: id)
            },
            parseProfile: { bytes, id in
                tally.countProfile()
                return ProfileParser.parse(bytes, as: id)
            }
        )
    }

    // MARK: - One parse per file

    func testEveryFileIsParsedOncePerReading() throws {
        let store = try store()
        defer { store.remove() }
        let tally = ParseTally()

        let reading = reading(of: store, tally: tally)

        XCTAssertEqual(reading.fragments, [ads, base])
        XCTAssertEqual(reading.profiles, [focus, work])
        XCTAssertEqual(tally.fragments, 2)
        XCTAssertEqual(tally.profiles, 2)
    }

    func testAskingForAnEntryCountIsNotASecondParse() throws {
        let store = try store()
        defer { store.remove() }
        let tally = ParseTally()
        let reading = reading(of: store, tally: tally)

        // The sidebar's rows, the layer rows and the composition's own report.
        for _ in 0..<3 {
            for id in reading.fragments {
                _ = reading.fragment(id)?.entryCount
            }
        }

        XCTAssertEqual(tally.fragments, 2, "a second question about a fragment is not a second parse")
        XCTAssertEqual(reading.fragment(base)?.entryCount, 2)
        XCTAssertEqual(reading.fragment(ads)?.entryCount, 1)
    }

    func testTwoCompositionsAndThreeRenderingsCostNoFurtherParses() throws {
        let store = try store()
        defer { store.remove() }
        let tally = ParseTally()
        let reading = reading(of: store, tally: tally)

        let workComposition = try reading.composition(of: work)
        let focusComposition = try reading.composition(of: focus)
        XCTAssertEqual(try reading.composition(of: work), workComposition)

        let workRendering = try reading.rendering(of: work)
        _ = try reading.rendering(of: focus)
        XCTAssertEqual(try reading.rendering(of: work), workRendering)
        XCTAssertEqual(workRendering, BlockRenderer.render(workComposition))
        XCTAssertEqual(focusComposition.resolved.count, 5)

        XCTAssertEqual(tally.fragments, 2, "composition reads the parse in hand")
        XCTAssertEqual(tally.profiles, 2)
    }

    /// A parse is held for a fragment some profile stacks, because composing
    /// needs it. A fragment nothing stacks is counted for its row and its parse
    /// let go: a blocklist of a hundred thousand entries that no profile uses
    /// is not worth forty megabytes for one number.
    func testAFragmentNothingStacksIsCountedButNotHeldParsed() throws {
        let store = try store()
        defer { store.remove() }
        try store.write("0.0.0.0\tone.example\n0.0.0.0\ttwo.example\n# hazmat:remove gone.example\n", to: "fragments/orphan.hosts")
        let tally = ParseTally()

        let reading = reading(of: store, tally: tally)
        let orphan = try XCTUnwrap(reading.fragment(FragmentID("orphan")))

        XCTAssertEqual(orphan.entryCount, 2)
        XCTAssertNil(orphan.outcome, "nothing stacks it, so its parse is not held")
        XCTAssertNotNil(reading.fragment(base)?.outcome, "a stacked fragment's parse is held for composing")
        XCTAssertEqual(reading.fragment(base)?.entryCount, 2)
        XCTAssertEqual(tally.fragments, 3, "counting it is still one parse")
    }

    func testACopyOfAReadingSharesItsDerivations() throws {
        let store = try store()
        defer { store.remove() }
        let tally = ParseTally()
        let reading = reading(of: store, tally: tally)

        let copy = reading
        _ = try copy.composition(of: work)
        _ = try reading.composition(of: work)

        XCTAssertEqual(tally.fragments, 2)
        XCTAssertEqual(tally.profiles, 2)
    }

    // MARK: - The same answers the composer gives by name

    func testTheReadingComposesWhatTheStoreDoes() throws {
        let store = try store()
        defer { store.remove() }

        let reading = StoreReading(layout: StoreLayout(root: store.root))
        let byName = try HostsComposer(store: DirectoryStore(root: store.root)).compose(profile: focus)

        XCTAssertEqual(try reading.composition(of: focus), byName)
        XCTAssertEqual(try reading.rendering(of: focus), BlockRenderer.render(byName))
    }

    // MARK: - Missing and malformed files

    func testAFileTheReadingCannotReadIsAbsentRatherThanAnError() throws {
        let store = try TempStore()
        defer { store.remove() }
        try store.write("missing\n", to: "profiles/work.profile")

        let reading = StoreReading(layout: StoreLayout(root: store.root))

        XCTAssertEqual(reading.profiles, [work])
        XCTAssertNil(reading.fragment(base))
        XCTAssertNil(reading.profile(focus))
        XCTAssertEqual(reading.profile(work)?.outcome.profile.references.count, 1)
    }

    func testAProfileThatCannotResolveReportsEveryProblemAtOnce() throws {
        let store = try TempStore()
        defer { store.remove() }
        try store.write("not an entry\n127.0.0.1 bad*name\n", to: "fragments/base.hosts")
        try store.write("base\nmissing\n", to: "profiles/work.profile")

        let reading = StoreReading(layout: StoreLayout(root: store.root))

        XCTAssertThrowsError(try reading.composition(of: work)) { error in
            guard let refusal = error as? CompositionError else { return XCTFail("expected a composition refusal") }
            XCTAssertEqual(refusal.problems, [
                .malformedEntry(fragment: base, line: 1, text: "not an entry", detail: .invalidAddress("not")),
                .malformedEntry(fragment: base, line: 2, text: "127.0.0.1 bad*name", detail: .invalidHostName("bad*name")),
                .missingFragment(profile: work, line: 2, fragment: FragmentID("missing"))
            ])
        }
    }

    func testAMissingProfileIsRefusedRatherThanComposedEmpty() throws {
        let store = try TempStore()
        defer { store.remove() }

        let reading = StoreReading(layout: StoreLayout(root: store.root))

        XCTAssertThrowsError(try reading.composition(of: work)) { error in
            XCTAssertEqual(error as? CompositionError, CompositionError([.missingProfile(work)]))
        }
    }

    // MARK: - Composing over parsed layers

    func testComposingOverParsedLayersRefusesWithEveryProblemAtOnce() {
        let parsed = FragmentParser.parse("127.0.0.1 localhost\nnot an entry\n", as: base)

        XCTAssertThrowsError(
            try HostsComposer.compose(
                profile: work,
                layers: [parsed.fragment],
                problems: parsed.problems + [.missingFragment(profile: work, line: 2, fragment: ads)]
            )
        ) { error in
            XCTAssertEqual((error as? CompositionError)?.problems.count, 2)
        }
    }

    func testComposingOverParsedLayersResolvesThem() throws {
        let baseOutcome = FragmentParser.parse("127.0.0.1\tlocalhost\n", as: base)
        let adsOutcome = FragmentParser.parse("127.0.0.1\tlocalhost\n", as: ads)

        let composition = try HostsComposer.compose(
            profile: work,
            layers: [baseOutcome.fragment, adsOutcome.fragment]
        )

        XCTAssertEqual(composition.resolved.map(\.name), ["localhost"])
        XCTAssertEqual(composition.displacements.count, 1)
        XCTAssertEqual(composition.displacements.first?.displacedBy.fragment, ads)
    }
}
