import XCTest
@testable import HazmatCore

final class SpliceTests: XCTestCase {
    private func renderedBlock() throws -> Data {
        BlockRenderer.render(try workComposition())
    }

    func testSplicePreservesEveryByteOutsideTheBlock() throws {
        let shipped = try Fixture.data("shipped-hosts", ext: "txt")
        let block = try renderedBlock()

        let spliced = try BlockSplice.splice(block: block, into: shipped)

        // The shipped bytes come through in order, behind the one separator the
        // splice adds, with the block after them.
        XCTAssertEqualBytes(Data(spliced.prefix(shipped.count)), shipped)
        XCTAssertEqual(Array(spliced[shipped.count..<(shipped.count + 1)]), [0x0A])
        XCTAssertEqualBytes(Data(spliced.suffix(block.count)), block)
        XCTAssertEqual(spliced.count, shipped.count + 1 + block.count)
    }

    func testTheDistributionHeaderAndLoopbackEntriesSurviveByteForByte() throws {
        let shipped = try Fixture.data("shipped-hosts", ext: "txt")
        let spliced = try BlockSplice.splice(block: try renderedBlock(), into: shipped)

        XCTAssertTrue(text(spliced).contains("# when the system is booting.  Do not change this entry.\n"))
        XCTAssertTrue(text(spliced).contains("127.0.0.1\tlocalhost\n"))
        XCTAssertTrue(text(spliced).contains("255.255.255.255\tbroadcasthost\n"))
        XCTAssertTrue(text(spliced).contains("::1             localhost\n"))
    }

    func testForeignEntriesKeepTheirOrderAndBytes() throws {
        let foreign = bytes("10.0.0.7\tsomewhere.example\n\n# another tool\n10.0.0.8\telsewhere.example   \n")
        let block = try renderedBlock()

        let spliced = try BlockSplice.splice(block: block, into: foreign)

        XCTAssertEqualBytes(Data(spliced.prefix(foreign.count)), foreign)
        XCTAssertEqualBytes(Data(spliced.suffix(block.count)), block)
    }

    func testReplacingABlockTouchesOnlyTheBlock() throws {
        let shipped = try Fixture.data("shipped-hosts", ext: "txt")
        let block = try renderedBlock()
        let spliced = try BlockSplice.splice(block: block, into: shipped)
        let replacement = BlockRenderer.render(
            try composition(fragments: [("base", "127.0.0.1\tnew.example\n")], profile: "base\n")
        )

        let replaced = try BlockSplice.splice(block: replacement, into: spliced)

        XCTAssertEqualBytes(Data(replaced.prefix(shipped.count)), shipped)
        XCTAssertEqualBytes(Data(replaced.suffix(replacement.count)), replacement)
        let location = try XCTUnwrap(ManagedBlock.locate(in: replaced))
        XCTAssertEqual(location.version, ManagedBlock.version)
        XCTAssertEqualBytes(Data(replaced[location.range]), replacement)
    }

    func testRoundTripRestoresThePreSpliceBytes() throws {
        let block = try renderedBlock()

        for name in ["shipped-hosts", "shipped-hosts-no-trailing-newline", "shipped-hosts-crlf", "empty-hosts"] {
            let original = try Fixture.data(name, ext: "txt")
            let spliced = try BlockSplice.splice(block: block, into: original)
            XCTAssertEqualBytes(try BlockSplice.strip(from: spliced), original, name)
        }
    }

    func testRoundTripAcrossManySurroundingContents() throws {
        let block = try renderedBlock()
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
            "   127.0.0.1\tlocalhost   \n"
        ]

        for original in surrounding {
            let spliced = try BlockSplice.splice(block: block, into: bytes(original))
            XCTAssertEqualBytes(try BlockSplice.strip(from: spliced), bytes(original), "\(Array(original.utf8))")
        }
    }

    func testSplicingAnAlreadyPresentBlockChangesNothing() throws {
        let block = try renderedBlock()
        let shipped = try Fixture.data("shipped-hosts", ext: "txt")
        let spliced = try BlockSplice.splice(block: block, into: shipped)

        XCTAssertEqualBytes(try BlockSplice.splice(block: block, into: spliced), spliced)
        XCTAssertEqualBytes(try BlockSplice.splice(block: block, into: try BlockSplice.splice(block: block, into: spliced)), spliced)
    }

    func testStrippingAFileWithNoBlockReturnsItUnchanged() throws {
        let shipped = try Fixture.data("shipped-hosts", ext: "txt")

        XCTAssertEqualBytes(try BlockSplice.strip(from: shipped), shipped)
    }

    func testRefusesASecondBlock() throws {
        let original = bytes(
            "# >>> hazmat:managed v1 >>>\n"
            + "127.0.0.1 localhost\n"
            + "# <<< hazmat:managed v1 <<<\n"
            + "# >>> hazmat:managed v1 >>>\n"
            + "# <<< hazmat:managed v1 <<<\n"
        )
        let file = original

        XCTAssertThrowsError(try BlockSplice.splice(block: try renderedBlock(), into: file)) { error in
            XCTAssertEqual(error as? BlockError, .multipleBlocks(firstLine: 1, secondLine: 4))
        }
        XCTAssertThrowsError(try BlockSplice.strip(from: file)) { error in
            XCTAssertEqual(error as? BlockError, .multipleBlocks(firstLine: 1, secondLine: 4))
        }
        XCTAssertEqualBytes(file, original)
    }

    func testRefusesAnUnterminatedBlock() throws {
        let file = bytes("# >>> hazmat:managed v1 >>>\n127.0.0.1 localhost\n")

        XCTAssertThrowsError(try BlockSplice.splice(block: try renderedBlock(), into: file)) { error in
            XCTAssertEqual(error as? BlockError, .unterminatedBlock(line: 1))
        }
        XCTAssertThrowsError(try BlockSplice.strip(from: file)) { error in
            XCTAssertEqual(error as? BlockError, .unterminatedBlock(line: 1))
        }
    }

    func testRefusesAnEndMarkerWithNoStart() throws {
        let file = bytes("127.0.0.1 localhost\n# <<< hazmat:managed v1 <<<\n")

        XCTAssertThrowsError(try BlockSplice.splice(block: try renderedBlock(), into: file)) { error in
            XCTAssertEqual(error as? BlockError, .endMarkerWithoutStart(line: 2))
        }
    }

    func testRefusesMalformedMarkers() throws {
        let cases: [(String, BlockError)] = [
            ("# >>> hazmat:managed >>>\n", .malformedMarker(line: 1, text: "# >>> hazmat:managed >>>")),
            ("# >>> hazmat:managed vX >>>\n", .malformedMarker(line: 1, text: "# >>> hazmat:managed vX >>>")),
            ("# >>> hazmat:managed v1 <<<\n", .malformedMarker(line: 1, text: "# >>> hazmat:managed v1 <<<")),
            ("# hazmat:managed v1 >>>\n", .malformedMarker(line: 1, text: "# hazmat:managed v1 >>>")),
            ("# a note about hazmat:managed markers\n", .malformedMarker(line: 1, text: "# a note about hazmat:managed markers"))
        ]

        for (content, expected) in cases {
            let file = bytes(content)
            XCTAssertThrowsError(try BlockSplice.splice(block: try renderedBlock(), into: file)) { error in
                XCTAssertEqual(error as? BlockError, expected, content)
            }
            XCTAssertThrowsError(try BlockSplice.strip(from: file)) { error in
                XCTAssertEqual(error as? BlockError, expected, content)
            }
        }
    }

    func testRefusesMarkersThatDisagreeAboutTheVersion() throws {
        let file = bytes("# >>> hazmat:managed v1 >>>\n# <<< hazmat:managed v2 <<<\n")

        XCTAssertThrowsError(try BlockSplice.splice(block: try renderedBlock(), into: file)) { error in
            XCTAssertEqual(error as? BlockError, .mismatchedVersions(startVersion: 1, endVersion: 2, line: 2))
        }
    }

    func testRefusesAFileWrittenByAnotherFormatVersion() throws {
        let file = bytes("# >>> hazmat:managed v2 >>>\n127.0.0.1 localhost\n# <<< hazmat:managed v2 <<<\n")

        XCTAssertThrowsError(try BlockSplice.splice(block: try renderedBlock(), into: file)) { error in
            XCTAssertEqual(error as? BlockError, .unsupportedVersion(found: 2, expected: 1))
        }
        // Reading reports the version instead of refusing it.
        XCTAssertEqual(try ManagedBlock.locate(in: file)?.version, 2)
    }

    func testRefusesAValueThatIsNotOneWholeBlock() throws {
        let block = try renderedBlock()

        XCTAssertThrowsError(try BlockSplice.splice(block: bytes("127.0.0.1 localhost\n"), into: bytes(""))) { error in
            XCTAssertEqual(error as? BlockError, .invalidBlock("it holds no managed block"))
        }
        XCTAssertThrowsError(try BlockSplice.splice(block: bytes("127.0.0.1 localhost\n") + block, into: bytes(""))) { error in
            XCTAssertEqual(error as? BlockError, .invalidBlock("it carries content outside its markers"))
        }
    }
}
