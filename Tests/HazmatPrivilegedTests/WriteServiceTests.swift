import Foundation
import HazmatCore
import HazmatProtocol
import XCTest
@testable import HazmatPrivileged

final class WriteServiceTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var service: PrivilegedWriteService!
    private var live: Data!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        live = appliedHosts()
        try directory.write(live)
        service = PrivilegedWriteService(target: directory.target, owner: testOwnership())
    }

    override func tearDown() {
        directory.remove()
        directory = nil
        service = nil
        live = nil
        super.tearDown()
    }

    private var digest: Data { BaselineDigest.of(live) }

    private func replacingBlock(with line: String) throws -> Data {
        let changed = text(live).replacingOccurrences(of: "127.0.0.1 hazmat.local\n", with: line)
        return bytes(changed)
    }

    // MARK: - 3.1 Validation before the file is touched

    func testRefusesBytesThatAreNotExactlyOneWellFormedSupportedBlock() throws {
        let cases: [(Data, WriteRefusal)] = [
            (bytes("127.0.0.1 localhost\n"), .noBlock),
            (
                bytes("# >>> hazmat:managed v2 >>>\n127.0.0.1 localhost\n# <<< hazmat:managed v2 <<<\n"),
                .block(.unsupportedVersion(found: 2, expected: 1))
            ),
            (
                bytes(
                    "# >>> hazmat:managed v1 >>>\n"
                        + "# <<< hazmat:managed v1 <<<\n"
                        + "# >>> hazmat:managed v1 >>>\n"
                        + "# <<< hazmat:managed v1 <<<\n"
                ),
                .block(.multipleBlocks(firstLine: 1, secondLine: 3))
            ),
            (
                bytes("# >>> hazmat:managed v1\n127.0.0.1 localhost\n"),
                .block(.malformedMarker(line: 1, text: "# >>> hazmat:managed v1"))
            ),
            (
                bytes("# >>> hazmat:managed v1 >>>\n127.0.0.1 localhost\n"),
                .block(.unterminatedBlock(line: 1))
            ),
            (
                Data(repeating: 0x61, count: PlannedBytes.sizeBound + 1),
                .oversized(actual: PlannedBytes.sizeBound + 1, bound: PlannedBytes.sizeBound)
            )
        ]

        for (bytes, refusal) in cases {
            XCTAssertEqual(service.write(bytes: bytes, baselineDigest: digest), .refused(refusal))
            XCTAssertEqualBytes(try directory.contents(), live, "the file changed for \(refusal)")
        }
    }

    func testAValidRequestReplacesTheFile() throws {
        let planned = try replacingBlock(with: "127.0.0.1 hazmat.local changed.example\n")

        XCTAssertEqual(service.write(bytes: planned, baselineDigest: digest), .written)
        XCTAssertEqualBytes(try directory.contents(), planned)
        XCTAssertEqual(try directory.entries(), ["hosts"])
    }

    /// The bound is a ceiling, not a target: a block of a hundred thousand short
    /// entries has to pass it, which is what makes a large store usable.
    func testALargeBlockWithinTheBoundIsNotRefusedForItsSize() throws {
        let block = largeBlock(entries: 100_000)
        let planned = try BlockSplice.splice(block: block, into: live)

        XCTAssertLessThan(planned.count, PlannedBytes.sizeBound)
        XCTAssertNil(PlannedBytes.refusal(planned), "a hundred thousand entries must pass the byte contract")
        XCTAssertEqual(service.write(bytes: planned, baselineDigest: digest), .written)
        XCTAssertEqualBytes(try directory.contents(), planned)
    }

    func testBytesOverTheBoundAreRefusedNamingBothNumbers() throws {
        let actual = PlannedBytes.sizeBound + 1
        let refusal = WriteRefusal.oversized(actual: actual, bound: PlannedBytes.sizeBound)

        XCTAssertEqual(
            service.write(bytes: Data(repeating: 0x61, count: actual), baselineDigest: digest),
            .refused(refusal)
        )
        XCTAssertTrue(refusal.description.contains("\(actual)"), refusal.description)
        XCTAssertTrue(refusal.description.contains("\(PlannedBytes.sizeBound)"), refusal.description)
        XCTAssertEqualBytes(try directory.contents(), live, "the file is unchanged")
    }

    /// A well-formed block with more entries than any hand-written fragment: the
    /// shape that would have hit the old one-megabyte bound.
    private func largeBlock(entries: Int) -> Data {
        var text = ManagedBlock.startMarker() + "\n"
        text.reserveCapacity(entries * 32)
        for index in 0..<entries {
            text += "10.0.0.\(index % 250 + 1) host-\(index).example.com\n"
        }
        text += ManagedBlock.endMarker() + "\n"
        return bytes(text)
    }

    // MARK: - Only the block may change

    func testRefusesBytesThatChangeTheFileOutsideTheBlock() throws {
        let cases: [(String, Data)] = [
            ("an entry added above the block", bytes(text(live).replacingOccurrences(of: "::1             localhost\n", with: "::1             localhost\n0.0.0.0 apple.com\n"))),
            ("an entry removed above the block", bytes(text(live).replacingOccurrences(of: "127.0.0.1\tlocalhost\n", with: ""))),
            ("an entry redirected above the block", bytes(text(live).replacingOccurrences(of: "127.0.0.1\tlocalhost", with: "10.0.0.1\tlocalhost"))),
            ("content appended after the block", bytes(text(live) + "10.0.0.9 trailing.example\n")),
            ("only the block, with the rest of the file dropped", bytes("# >>> hazmat:managed v1 >>>\n127.0.0.1 hazmat.local\n# <<< hazmat:managed v1 <<<\n"))
        ]

        for (label, planned) in cases {
            XCTAssertNil(PlannedBytes.refusal(planned), "\(label) must pass the byte contract on its own")
            XCTAssertEqual(service.write(bytes: planned, baselineDigest: digest), .refused(.bytesOutsideBlockChanged), label)
            XCTAssertEqualBytes(try directory.contents(), live, "the file changed for \(label)")
        }
    }

    func testAFirstApplyChangesNothingButTheSeparatorItInserts() throws {
        // A first apply lands a block behind one `\n`; stripping the block takes
        // the separator with it, so the file outside the block is unchanged.
        let plain = bytes("127.0.0.1\tlocalhost\n::1\tlocalhost\n")
        try directory.write(plain)
        let block = bytes("# >>> hazmat:managed v1 >>>\n127.0.0.1 hazmat.local\n# <<< hazmat:managed v1 <<<\n")
        let planned = try BlockSplice.splice(block: block, into: plain)

        XCTAssertEqual(service.write(bytes: planned, baselineDigest: BaselineDigest.of(plain)), .written)
        XCTAssertEqualBytes(try directory.contents(), planned)
    }

    func testALiveFileWhoseMarkersCannotBeReadIsNeverWrittenOver() throws {
        let unterminated = bytes("127.0.0.1\tlocalhost\n# >>> hazmat:managed v1 >>>\n127.0.0.1 hazmat.local\n")
        try directory.write(unterminated)
        let planned = bytes("127.0.0.1\tlocalhost\n# >>> hazmat:managed v1 >>>\n127.0.0.1 hazmat.local\n# <<< hazmat:managed v1 <<<\n")

        XCTAssertEqual(
            service.write(bytes: planned, baselineDigest: BaselineDigest.of(unterminated)),
            .refused(.block(.unterminatedBlock(line: 2)))
        )
        XCTAssertEqualBytes(try directory.contents(), unterminated)
    }

    // MARK: - 3.6 The request carries the state the plan was based on

    func testRefusesAWriteWhenTheFileNoLongerMatchesTheBaseline() throws {
        let planned = try replacingBlock(with: "127.0.0.1 hazmat.local changed.example\n")
        let stale = digest

        let edit = bytes(text(live) + "10.0.0.9\tedited.example\n")
        try directory.write(edit)

        XCTAssertEqual(service.write(bytes: planned, baselineDigest: stale), .refused(.baselineMismatch))
        XCTAssertEqualBytes(try directory.contents(), edit, "the concurrent edit must survive")
    }

    func testAWriteIsPerformedWhenTheFileStillMatches() throws {
        let planned = try replacingBlock(with: "127.0.0.1 hazmat.local changed.example\n")

        XCTAssertEqual(service.write(bytes: planned, baselineDigest: BaselineDigest.of(try directory.contents())), .written)
        XCTAssertEqualBytes(try directory.contents(), planned)
    }

    func testAMissingFileIsRefusedRatherThanWritten() throws {
        let planned = try replacingBlock(with: "127.0.0.1 hazmat.local changed.example\n")
        try FileManager.default.removeItem(at: directory.target)

        XCTAssertEqual(service.write(bytes: planned, baselineDigest: digest), .refused(.baselineMismatch))
    }

    // MARK: - Removal

    func testRemovalStripsTheBlockFromTheFileThePlanWasBasedOn() throws {
        XCTAssertEqual(service.removeBlock(baselineDigest: digest), .written)
        XCTAssertEqualBytes(try BlockSplice.strip(from: live), try directory.contents())
        XCTAssertFalse(text(try directory.contents()).contains("hazmat:managed"))
    }

    func testRemovalRefusesAStaleBaselineAndKeepsTheEdit() throws {
        let edit = bytes(text(live) + "10.0.0.9\tedited.example\n")
        try directory.write(edit)

        XCTAssertEqual(service.removeBlock(baselineDigest: digest), .refused(.baselineMismatch))
        XCTAssertEqualBytes(try directory.contents(), edit)
    }

    func testRemovalRefusesAFileWithNoBlock() throws {
        let plain = bytes("127.0.0.1 localhost\n")
        try directory.write(plain)

        XCTAssertEqual(service.removeBlock(baselineDigest: BaselineDigest.of(plain)), .refused(.noBlock))
        XCTAssertEqualBytes(try directory.contents(), plain)
    }

    func testRemovalRefusesAFileWithADoubledMarkerSet() throws {
        let doubled = bytes(
            "# >>> hazmat:managed v1 >>>\n"
                + "# <<< hazmat:managed v1 <<<\n"
                + "# >>> hazmat:managed v1 >>>\n"
                + "# <<< hazmat:managed v1 <<<\n"
        )
        try directory.write(doubled)

        XCTAssertEqual(
            service.removeBlock(baselineDigest: BaselineDigest.of(doubled)),
            .refused(.block(.multipleBlocks(firstLine: 1, secondLine: 3)))
        )
        XCTAssertEqualBytes(try directory.contents(), doubled)
    }

    func testTheDigestIsTheOneBothSidesCompute() throws {
        XCTAssertEqual(BaselineDigest.of(bytes("")), BaselineDigest.of(Data()))
        XCTAssertNotEqual(BaselineDigest.of(bytes("a")), BaselineDigest.of(bytes("b")))
        XCTAssertEqual(BaselineDigest.of(bytes("a")).count, 32)
    }
}
