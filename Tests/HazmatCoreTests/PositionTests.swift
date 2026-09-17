import XCTest
@testable import HazmatCore

final class PositionTests: XCTestCase {
    func testBothPositionsRoundTripToTheOriginalBytes() throws {
        let block = try renderedWorkBlock()
        // A file that already holds a block is replaced in place rather than
        // spliced, so the round trip starts from a file that holds none.
        let names = ["shipped-hosts", "shipped-hosts-no-trailing-newline", "shipped-hosts-crlf", "empty-hosts"]

        for name in names {
            let original = try Fixture.data(name, ext: "txt")
            for position in BlockPosition.allCases {
                let spliced = try BlockSplice.splice(block: block, into: original, at: position)
                XCTAssertEqualBytes(try BlockSplice.strip(from: spliced), original, "\(name) at \(position)")
            }
        }
    }

    func testBothPositionsRoundTripAcrossManySurroundingContents() throws {
        let block = try renderedWorkBlock()
        let surrounding = [
            "",
            "\n",
            "\n\n",
            "abc",
            "abc\n",
            "abc\n\n",
            "abc\r",
            "abc\r\n",
            "# only a comment\n",
            "\t \n",
            "   127.0.0.1\tlocalhost   \n",
            "# header\n\n# more header\n127.0.0.1\tfirst\n10.0.0.7\tlater\n"
        ]

        for original in surrounding {
            for position in BlockPosition.allCases {
                let spliced = try BlockSplice.splice(block: block, into: bytes(original), at: position)
                XCTAssertEqualBytes(
                    try BlockSplice.strip(from: spliced),
                    bytes(original),
                    "\(Array(original.utf8)) at \(position)"
                )
            }
        }
    }

    func testBeforeFirstEntryLandsBehindTheLastHeaderLineAndBeforeTheFirstEntry() throws {
        let shipped = try shippedHosts()
        let block = try renderedWorkBlock()
        let spliced = try BlockSplice.splice(block: block, into: shipped, at: .beforeFirstEntry)

        let entryIndex = BlockSplice.firstEntryIndex(in: shipped)
        XCTAssertEqualBytes(Data(shipped[entryIndex...].prefix(10)), bytes("127.0.0.1\t"))

        let location = try XCTUnwrap(ManagedBlock.locate(in: spliced))
        XCTAssertEqual(location.range.lowerBound, entryIndex + 1)

        // The prefix is the shipped bytes up to the first entry, then the one
        // separator, then the block, then the untouched remainder.
        XCTAssertEqualBytes(Data(spliced[..<entryIndex]), Data(shipped[..<entryIndex]))
        XCTAssertEqualBytes(Data(spliced[entryIndex..<location.range.lowerBound]), bytes("\n"))
        XCTAssertEqualBytes(Data(spliced[location.range]), block)
        XCTAssertEqualBytes(Data(spliced[location.range.upperBound...]), Data(shipped[entryIndex...]))
    }

    func testEndOfFileLandsBehindTheWholeFile() throws {
        let shipped = try shippedHosts()
        let block = try renderedWorkBlock()
        let spliced = try BlockSplice.splice(block: block, into: shipped, at: .endOfFile)

        XCTAssertEqualBytes(Data(spliced.prefix(shipped.count)), shipped)
        XCTAssertEqualBytes(Data(spliced.suffix(block.count)), block)
    }

    func testEveryOtherLineKeepsItsRelativeOrderAtBothPositions() throws {
        let foreign = bytes("# header\n10.0.0.7\tfirst.example\n\n10.0.0.8\tsecond.example\n")
        let block = try renderedWorkBlock()

        for position in BlockPosition.allCases {
            let spliced = try BlockSplice.splice(block: block, into: foreign, at: position)
            let remaining = try BlockSplice.strip(from: spliced)
            XCTAssertEqualBytes(remaining, foreign, "\(position)")
            // The foreign lines are still in their original order, with their
            // blank line and trailing newline intact.
            XCTAssertEqual(text(remaining), text(foreign))
        }
    }

    func testFirstEntryIndexSkipsBlankAndCommentLines() {
        XCTAssertEqual(BlockSplice.firstEntryIndex(in: bytes("")), 0)
        XCTAssertEqual(BlockSplice.firstEntryIndex(in: bytes("# a\n# b\n")), 8)
        XCTAssertEqual(BlockSplice.firstEntryIndex(in: bytes("\n\n# a\n127.0.0.1 x\n")), 6)
        XCTAssertEqual(BlockSplice.firstEntryIndex(in: bytes("   \t \n# a\n")), 10)
        XCTAssertEqual(BlockSplice.firstEntryIndex(in: bytes("   \t \n127.0.0.1 x\n")), 6)
        XCTAssertEqual(BlockSplice.firstEntryIndex(in: bytes("127.0.0.1 x\n")), 0)
        XCTAssertEqual(BlockSplice.firstEntryIndex(in: bytes("127.0.0.1 x")), 0)
        XCTAssertEqual(BlockSplice.firstEntryIndex(in: bytes("# a\r\n127.0.0.1 x\r\n")), 5)
    }

    func testAnExistingBlockIsReplacedWhereItIsRatherThanMoved() throws {
        let shipped = try shippedHosts()
        let first = try renderedWorkBlock()
        let second = BlockRenderer.render(
            try composition(fragments: [("base", "127.0.0.1\tnew.example\n")], profile: "base\n")
        )

        let applied = try BlockSplice.splice(block: first, into: shipped, at: .endOfFile)
        let replaced = try BlockSplice.splice(block: second, into: applied, at: .beforeFirstEntry)

        XCTAssertEqualBytes(try BlockSplice.strip(from: replaced), shipped)
        XCTAssertEqualBytes(Data(replaced.suffix(second.count)), second)
    }

    func testAnApplyNamingAPositionLandsTheBlockThere() throws {
        let shipped = try shippedHosts()
        let block = try renderedWorkBlock()
        let target = try TemporaryHostsFile(shipped)
        defer { target.remove() }
        let writer = RecordingWriter()
        let applier = HostsFileApplier(fileURL: target.url, writer: writer)

        XCTAssertEqual(applier.apply(block: block, position: .beforeFirstEntry), .applied(.installedBlock))

        let planned = try XCTUnwrap(writer.writes.last?.bytes)
        let location = try XCTUnwrap(ManagedBlock.locate(in: planned))
        XCTAssertEqual(location.range.lowerBound, BlockSplice.firstEntryIndex(in: shipped) + 1)
        // The default is set by the resolver measurement recorded in design.md.
        XCTAssertTrue(BlockPosition.allCases.contains(BlockPosition.default))
    }
}
