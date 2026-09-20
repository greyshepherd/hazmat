import Dispatch
import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

/// The generated store, built once per test process: writing seven megabytes of
/// fixtures costs more than the reads being measured. Nothing here writes into
/// the repository.
enum ScaleFixture {
    static let entries = 100_000
    static let overrides = 50_000

    static let big = FragmentID("big")
    static let overriding = FragmentID("override")
    static let wide = ProfileID("wide")
    static let stacked = ProfileID("stacked")
    static let reversed = ProfileID("reversed")

    /// Every profile a read has to render when the live file holds a block.
    static let profiles = [wide, stacked, reversed]

    /// `10.0.0.7 host-000123.example.com alias-000123.example.com`, so the
    /// fragment is a little under six megabytes for a hundred thousand lines.
    static func fragment(entries: Int = entries) -> String {
        var text = ""
        text.reserveCapacity(entries * 60)
        for index in 0..<entries {
            let number = padded(index)
            text += "10.0.0.\(index % 250 + 1) host-\(number).example.com alias-\(number).example.com\n"
        }
        return text
    }

    /// `0.0.0.0 host-000123.example.com`, which overrides the name the fragment
    /// above gave the same line.
    static func layer(overrides: Int = overrides) -> String {
        var text = ""
        text.reserveCapacity(overrides * 34)
        for index in 0..<overrides {
            text += "0.0.0.0 host-\(padded(index)).example.com\n"
        }
        return text
    }

    private static func padded(_ value: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }
}

/// The fixture on disk, and the live file that holds one of its blocks.
struct ScaleWorld {
    let root: URL
    let liveURL: URL
    let bigText: String
    let layerText: String
    let liveBytes: Data

    static let shipped = Data("127.0.0.1\tlocalhost\n".utf8)

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hazmat-scale-\(UUID().uuidString)")
        let fragments = root.appendingPathComponent("fragments", isDirectory: true)
        let profiles = root.appendingPathComponent("profiles", isDirectory: true)
        try FileManager.default.createDirectory(at: fragments, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)

        let bigText = ScaleFixture.fragment()
        let layerText = ScaleFixture.layer()
        try bigText.write(to: fragments.appendingPathComponent("big.hosts"), atomically: true, encoding: .utf8)
        try layerText.write(to: fragments.appendingPathComponent("override.hosts"), atomically: true, encoding: .utf8)
        try "big\n".write(to: profiles.appendingPathComponent("wide.profile"), atomically: true, encoding: .utf8)
        try "big\noverride\n".write(to: profiles.appendingPathComponent("stacked.profile"), atomically: true, encoding: .utf8)
        try "override\nbig\n".write(to: profiles.appendingPathComponent("reversed.profile"), atomically: true, encoding: .utf8)

        let block = BlockRenderer.render(
            try HostsComposer(store: DirectoryStore(root: root)).compose(profile: ScaleFixture.stacked)
        )
        let liveBytes = ScaleWorld.shipped + Data([0x0A]) + block
        let liveURL = root.appendingPathComponent("hosts")
        try liveBytes.write(to: liveURL, options: .atomic)

        self.root = root
        self.liveURL = liveURL
        self.bigText = bigText
        self.layerText = layerText
        self.liveBytes = liveBytes
    }

    func session() -> StoreSession {
        StoreSession(root: root, fileURL: liveURL, writer: UnregisteredHelper())
    }

    var liveReading: LiveHostsFile { LiveHostsFile(url: liveURL) }

    var liveSize: Int { liveBytes.count }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// The numbers the change is judged by, printed through stderr so the test
/// runner's own capture does not swallow them.
final class ScaleTests: XCTestCase {
    nonisolated(unsafe) private static var built: ScaleWorld?
    private var world: ScaleWorld!

    override func setUpWithError() throws {
        if let built = Self.built {
            world = built
        } else {
            let built = try ScaleWorld()
            Self.built = built
            world = built
        }
    }

    override func tearDown() {
        world = nil
        super.tearDown()
    }

    override class func tearDown() {
        Self.built?.remove()
        Self.built = nil
        super.tearDown()
    }

    /// The fixture is the one the proposal measured, so a target that holds here
    /// says something about the store it was written for.
    func testTheGeneratedStoreIsTheFixtureTheProposalMeasured() throws {
        let parsed = FragmentParser.parse(world.bigText, as: ScaleFixture.big)
        XCTAssertEqual(parsed.problems, [])
        XCTAssertEqual(parsed.fragment.entries.count, ScaleFixture.entries)

        let composed = try HostsComposer(store: DirectoryStore(root: world.root))
            .compose(profile: ScaleFixture.stacked)
        // The overriding layer displaces one name per line and supplies one
        // winner per line, so the resolved set holds two names per entry.
        XCTAssertEqual(composed.displacements.count, ScaleFixture.overrides)
        XCTAssertEqual(composed.resolved.count, ScaleFixture.entries * 2)
        XCTAssertEqual(BlockRenderer.entries(composed).count, ScaleFixture.entries * 3 / 2)

        report("fixture fragment", world.bigText.utf8.count)
        report("fixture live file", world.liveSize)
        XCTAssertGreaterThan(world.liveSize, 6 << 20, "the locate target is measured on a six megabyte file")
    }

    func testParsingMeetsItsTarget() throws {
        // Once outside the measurement, so the first pass is not paying for
        // lazily warmed code paths.
        _ = FragmentParser.parse(world.layerText, as: ScaleFixture.overriding)

        let milliseconds = timed("parse 100,000 lines") {
            _ = FragmentParser.parse(world.bigText, as: ScaleFixture.big)
        }

        #if !DEBUG
        XCTAssertLessThan(milliseconds, 150, "parsing a 100,000-line fragment")
        #endif
    }

    func testComposingAndRenderingMeetTheirTargets() throws {
        let store = DirectoryStore(root: world.root)
        _ = try HostsComposer(store: store).compose(profile: ScaleFixture.wide)

        var composition: Composition?
        try timed("compose stacked") {
            composition = try HostsComposer(store: store).compose(profile: ScaleFixture.stacked)
        }
        let stacked = try XCTUnwrap(composition)
        timed("render stacked") { _ = BlockRenderer.render(stacked) }
    }

    func testLocatingMeetsItsTarget() throws {
        _ = try ManagedBlock.locate(in: ScaleWorld.shipped)

        let milliseconds = try timed("locate \(world.liveSize >> 20) MB") {
            _ = try ManagedBlock.locate(in: world.liveBytes)
        }

        #if !DEBUG
        XCTAssertLessThan(milliseconds, 20, "locating the block in a six megabyte file")
        #endif
    }

    func testAReadIsColdFastAndWarmFast() throws {
        let session = world.session()
        let selection: SidebarSelection = .profile(ScaleFixture.stacked)

        let cold = timed("read cold") { _ = session.editor.read(selection: selection) }
        var warm: [Double] = []
        for _ in 1..<passes {
            warm.append(timed("read warm") { _ = session.editor.read(selection: selection) })
        }

        #if !DEBUG
        XCTAssertLessThan(cold, 300, "a cold read of the 100,000-line store")
        XCTAssertLessThan(warm.max() ?? Double.infinity, 30, "a warm read of the 100,000-line store")
        #endif
    }

    func testActivationIsFastWarm() throws {
        let session = world.session()

        let cold = timed("activation cold") {
            _ = session.catalogue.activation(reading: session.liveFile)
        }
        var warm: [Double] = []
        for _ in 1..<passes {
            warm.append(timed("activation warm") {
                _ = session.catalogue.activation(reading: session.liveFile)
            })
        }

        #if !DEBUG
        XCTAssertLessThan(cold, 500, "a cold derivation over the 100,000-line store")
        XCTAssertLessThan(warm.max() ?? Double.infinity, 30, "a warm derivation over the 100,000-line store")
        #endif
    }

    // MARK: - Timing

    /// A debug build is not optimised and its timings say nothing about the
    /// targets, so only one pass is measured there and the release-only
    /// assertions are skipped: the debug suite is never gated on optimisation.
    private var passes: Int {
        #if DEBUG
        return 1
        #else
        return 4
        #endif
    }

    /// Runs `body` once and prints how long it took, in milliseconds.
    @discardableResult
    private func timed(_ label: String, _ body: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try body()
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        FileHandle.standardError.write(Data(String(format: "ScaleTests %@: %.1f ms\n", label, milliseconds).utf8))
        return milliseconds
    }

    private func report(_ label: String, _ value: Int) {
        FileHandle.standardError.write(Data("ScaleTests \(label): \(value) bytes\n".utf8))
    }
}
