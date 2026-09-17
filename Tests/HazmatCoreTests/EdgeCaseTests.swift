import XCTest
@testable import HazmatCore

final class EdgeCaseTests: XCTestCase {
    private func shipped() throws -> Data {
        try Fixture.data("shipped-hosts", ext: "txt")
    }

    func testAnEmptyResolvedSetRendersAMarkersOnlyBlock() throws {
        let composition = try composition(fragments: [("empty", "# nothing to resolve\n")], profile: "empty\n")

        let block = BlockRenderer.render(composition)

        XCTAssertTrue(composition.isEmpty)
        XCTAssertEqual(
            text(block),
            "# >>> hazmat:managed v1 >>>\n"
            + "# <<< hazmat:managed v1 <<<\n"
        )
    }

    func testAnEmptyBlockIsDistinguishableFromAnUnmanagedFile() throws {
        let block = BlockRenderer.render(try composition(fragments: [("empty", "")], profile: "empty\n"))

        XCTAssertNotNil(try ManagedBlock.locate(in: block))
        XCTAssertNil(try ManagedBlock.locate(in: try shipped()))
    }

    func testAnEmptyBlockIsRemovableByTheSamePath() throws {
        let block = BlockRenderer.render(try composition(fragments: [("empty", "")], profile: "empty\n"))
        let original = try shipped()

        let spliced = try BlockSplice.splice(block: block, into: original)

        XCTAssertEqualBytes(Data(spliced.prefix(original.count)), original)
        XCTAssertEqualBytes(try BlockSplice.strip(from: spliced), original)
    }

    func testACRLFFileKeepsItsLineEndings() throws {
        let original = try Fixture.data("shipped-hosts-crlf", ext: "txt")
        let block = BlockRenderer.render(try workComposition())

        let spliced = try BlockSplice.splice(block: block, into: original)

        XCTAssertEqualBytes(Data(spliced.prefix(original.count)), original)
        XCTAssertTrue(text(Data(spliced.prefix(original.count))).contains("\r\n"))
        XCTAssertEqualBytes(try BlockSplice.strip(from: spliced), original)
    }

    func testACRLFFileThatAlreadyHoldsABlockIsRecognised() throws {
        let block = BlockRenderer.render(try workComposition())
        let crlfBlock = bytes(text(block).replacingOccurrences(of: "\n", with: "\r\n"))
        let file = bytes("127.0.0.1\tlocalhost\r\n") + crlfBlock

        let location = try XCTUnwrap(ManagedBlock.locate(in: file))

        XCTAssertEqual(location.startLine, 2)
        XCTAssertEqualBytes(try BlockSplice.splice(block: block, into: file), bytes("127.0.0.1\tlocalhost\r\n") + block)
    }

    func testAFileWithNoTrailingNewlineIsPreserved() throws {
        let original = try Fixture.data("shipped-hosts-no-trailing-newline", ext: "txt")
        let block = BlockRenderer.render(try workComposition())

        let spliced = try BlockSplice.splice(block: block, into: original)

        XCTAssertEqualBytes(Data(spliced.prefix(original.count)), original)
        XCTAssertEqual(Array(spliced[original.count..<(original.count + 1)]), [0x0A])
        XCTAssertEqualBytes(try BlockSplice.strip(from: spliced), original)
    }

    func testAnEmptyFileIsPreserved() throws {
        let original = try Fixture.data("empty-hosts", ext: "txt")
        let block = BlockRenderer.render(try workComposition())

        XCTAssertEqual(original.count, 0)
        let spliced = try BlockSplice.splice(block: block, into: original)

        XCTAssertEqualBytes(spliced, bytes("\n") + block)
        XCTAssertEqualBytes(try BlockSplice.strip(from: spliced), original)
    }

    func testAMarkerOnlyFileIsReplacedInPlaceAndRemoved() throws {
        let original = try Fixture.data("marker-only-hosts", ext: "txt")
        let block = BlockRenderer.render(try workComposition())

        let spliced = try BlockSplice.splice(block: block, into: original)

        XCTAssertEqualBytes(spliced, block)
        XCTAssertEqualBytes(try BlockSplice.splice(block: block, into: spliced), spliced)
        XCTAssertEqualBytes(try BlockSplice.strip(from: spliced), bytes(""))
    }

    func testAMarkerOnlyFileIsAnEmptyBlock() throws {
        let original = try Fixture.data("marker-only-hosts", ext: "txt")

        let location = try XCTUnwrap(ManagedBlock.locate(in: original))

        XCTAssertEqual(location.version, ManagedBlock.version)
        XCTAssertEqualBytes(Data(original[location.range]), original)
        XCTAssertEqual(
            text(original),
            text(BlockRenderer.render(try composition(fragments: [("empty", "")], profile: "empty\n")))
        )
    }
}
