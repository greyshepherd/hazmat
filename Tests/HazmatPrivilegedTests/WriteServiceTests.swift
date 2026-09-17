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
