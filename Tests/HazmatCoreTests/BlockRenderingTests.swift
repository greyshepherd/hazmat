import XCTest
@testable import HazmatCore

final class BlockRenderingTests: XCTestCase {
    func testRenderedOutputCarriesBothMarkers() throws {
        let block = BlockRenderer.render(try workComposition())

        XCTAssertTrue(text(block).hasPrefix(ManagedBlock.startMarker() + "\n"))
        XCTAssertTrue(text(block).hasSuffix(ManagedBlock.endMarker() + "\n"))
        XCTAssertEqual(text(block).split(separator: "\n").filter { $0.contains(ManagedBlock.token) }.count, 2)
    }

    func testBlockBoundariesAreLocatedWithoutLineNumbers() throws {
        let block = BlockRenderer.render(try workComposition())
        let file = bytes("255.255.255.255\tbroadcasthost\n") + bytes("# a comment\n") + block + bytes("10.0.0.1\tlater.example\n")

        let location = try XCTUnwrap(ManagedBlock.locate(in: file))

        XCTAssertEqual(location.version, ManagedBlock.version)
        XCTAssertEqualBytes(Data(file[location.range]), block)
        XCTAssertEqual(location.startLine, 3)
    }

    func testBlockIsAbsentFromAnUnmanagedFile() throws {
        XCTAssertNil(try ManagedBlock.locate(in: try Fixture.data("shipped-hosts", ext: "txt")))
    }

    func testTheVersionABlockWasWrittenWithIsReported() throws {
        let file = bytes("# >>> hazmat:managed v9 >>>\n127.0.0.1 localhost\n# <<< hazmat:managed v9 <<<\n")

        let location = try XCTUnwrap(ManagedBlock.locate(in: file))

        XCTAssertEqual(location.version, 9)
    }

    func testRenderedBlockMatchesTheFixtureByteForByte() throws {
        let block = BlockRenderer.render(try workComposition())

        XCTAssertEqualBytes(block, try Fixture.data("expected-work-block", ext: "txt"))
    }

    /// The count of a block is asked far more often than the block's lines
    /// are wanted, so it is counted without building them.
    func testTheEntryCountIsTheNumberOfLinesTheRendererWrites() throws {
        let composition = try workComposition()

        XCTAssertEqual(BlockRenderer.entryCount(composition), BlockRenderer.entries(composition).count)
        XCTAssertEqual(BlockRenderer.entryCount(composition), 5, "names one entry supplied share a line")
    }

    func testEveryNameIsEmittedOncePerFamily() throws {
        let block = text(BlockRenderer.render(try workComposition()))
        let entries = block.split(separator: "\n").filter { !$0.hasPrefix("#") }

        XCTAssertEqual(entries, [
            "127.0.0.1 localhost hazmat.local",
            "::1 api.internal",
            "127.0.0.1 api.internal api",
            "::1 localhost",
            "0.0.0.0 ads.example.com telemetry.example.com"
        ])

        let emitted = entries.flatMap { $0.split(separator: " ").dropFirst().map(String.init) }
        XCTAssertEqual(emitted.filter { $0 == "api.internal" }.count, 2)
        XCTAssertEqual(emitted.filter { $0 == "localhost" }.count, 2)
        XCTAssertEqual(emitted.filter { $0 == "legacy.example.com" }.count, 0)
        XCTAssertEqual(emitted.filter { $0 == "docs.internal" }.count, 0)
    }

    func testRepeatedRenderingIsByteIdentical() throws {
        let composition = try workComposition()

        XCTAssertEqualBytes(BlockRenderer.render(composition), BlockRenderer.render(composition))
    }

    func testEnumerationOrderDoesNotChangeTheBytes() throws {
        let forward = InMemoryStore(
            fragments: [
                FragmentID("base"): "10.0.0.5\tapi.example.com\n127.0.0.1\tlocalhost\n",
                FragmentID("project"): "127.0.0.1\tapi.example.com api\n",
                FragmentID("blocklist"): "0.0.0.0\tads.example.com\n"
            ],
            profiles: [ProfileID("work"): "base\nproject\nblocklist\n"]
        )
        let reversed = InMemoryStore(
            fragments: [
                FragmentID("blocklist"): "0.0.0.0\tads.example.com\n",
                FragmentID("project"): "127.0.0.1\tapi.example.com api\n",
                FragmentID("base"): "10.0.0.5\tapi.example.com\n127.0.0.1\tlocalhost\n"
            ],
            profiles: [ProfileID("work"): "base\nproject\nblocklist\n"]
        )

        let first = BlockRenderer.render(try HostsComposer(store: forward).compose(profile: ProfileID("work")))
        let second = BlockRenderer.render(try HostsComposer(store: reversed).compose(profile: ProfileID("work")))

        XCTAssertEqualBytes(first, second)
    }

    func testRenderingAnEmptyCompositionEmitsMarkersOnly() throws {
        let composition = try composition(fragments: [("empty", "# nothing\n")], profile: "empty\n")

        XCTAssertTrue(composition.isEmpty)
        XCTAssertEqual(
            text(BlockRenderer.render(composition)),
            "# >>> hazmat:managed v1 >>>\n# <<< hazmat:managed v1 <<<\n"
        )
    }
}
