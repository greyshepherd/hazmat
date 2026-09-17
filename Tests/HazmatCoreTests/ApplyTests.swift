import XCTest
@testable import HazmatCore

/// Records what the applier asked for, without touching any file.
final class RecordingWriter: PrivilegedWriter, @unchecked Sendable {
    private(set) var writes: [(bytes: Data, baseline: Data)] = []
    private(set) var removals: [Data] = []
    var result: PrivilegedWriteResult = .written

    func write(bytes: Data, baseline: Data) -> PrivilegedWriteResult {
        writes.append((bytes, baseline))
        return result
    }

    func removeBlock(baseline: Data) -> PrivilegedWriteResult {
        removals.append(baseline)
        return result
    }
}

/// Performs the write the way the daemon would - the same compare-and-swap, the
/// same atomic replace - but in the test process and against the injected path.
final class LocalWriter: PrivilegedWriter, @unchecked Sendable {
    let target: URL
    private(set) var writeCount = 0
    private(set) var removalCount = 0

    init(target: URL) {
        self.target = target
    }

    func write(bytes: Data, baseline: Data) -> PrivilegedWriteResult {
        guard let live = try? Data(contentsOf: target), live == baseline else {
            return .refused(reason: "the file changed since it was read")
        }
        do {
            try bytes.write(to: target, options: .atomic)
            writeCount += 1
            return .written
        } catch {
            return .failed(reason: "\(error)")
        }
    }

    func removeBlock(baseline: Data) -> PrivilegedWriteResult {
        guard let live = try? Data(contentsOf: target), live == baseline else {
            return .refused(reason: "the file changed since it was read")
        }
        do {
            let stripped = try BlockSplice.strip(from: live)
            try stripped.write(to: target, options: .atomic)
            removalCount += 1
            return .written
        } catch {
            return .failed(reason: "\(error)")
        }
    }
}

/// A throwaway file with the fixture bytes, standing in for the live file.
final class TemporaryHostsFile {
    let url: URL

    init(_ contents: Data) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hazmat-\(UUID().uuidString)-hosts")
        try contents.write(to: url)
    }

    var bytes: Data {
        (try? Data(contentsOf: url)) ?? Data()
    }

    func snapshot() throws -> FileSnapshot {
        try currentSnapshot(of: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

func renderedWorkBlock() throws -> Data {
    BlockRenderer.render(try workComposition())
}

func shippedHosts() throws -> Data {
    try Fixture.data("shipped-hosts", ext: "txt")
}

final class ApplyTests: XCTestCase {
    private var files: [TemporaryHostsFile] = []

    override func tearDown() {
        files.forEach { $0.remove() }
        files = []
        super.tearDown()
    }

    private func file(_ contents: Data) throws -> TemporaryHostsFile {
        let created = try TemporaryHostsFile(contents)
        files.append(created)
        return created
    }

    // MARK: - 2.1 Every block state

    func testClassifiesEveryBlockStateFromFixtureBytes() throws {
        let rendered = try renderedWorkBlock()
        let shipped = try shippedHosts()
        let applied = try BlockSplice.splice(block: rendered, into: shipped)
        let drifted = bytes(text(applied).replacingOccurrences(of: "api.internal", with: "api.changed"))
        let doubled = bytes(
            "# >>> hazmat:managed v1 >>>\n"
                + "# <<< hazmat:managed v1 <<<\n"
                + "# >>> hazmat:managed v1 >>>\n"
                + "# <<< hazmat:managed v1 <<<\n"
        )
        let cases: [(Data, BlockState)] = [
            (shipped, .absent),
            (applied, .unchanged),
            (drifted, .drifted),
            (doubled, .refused(.multipleBlocks(firstLine: 1, secondLine: 3))),
            (
                bytes("# >>> hazmat:managed v2 >>>\n127.0.0.1 localhost\n# <<< hazmat:managed v2 <<<\n"),
                .refused(.unsupportedVersion(found: 2, expected: 1))
            ),
            (
                bytes("# >>> hazmat:managed v1\n127.0.0.1 localhost\n"),
                .refused(.malformedMarker(line: 1, text: "# >>> hazmat:managed v1"))
            ),
            (
                bytes("127.0.0.1 localhost\n# <<< hazmat:managed v1 <<<\n"),
                .refused(.endMarkerWithoutStart(line: 2))
            ),
            (bytes("# >>> hazmat:managed v1 >>>\n127.0.0.1 localhost\n"), .refused(.unterminatedBlock(line: 1)))
        ]

        for (contents, expected) in cases {
            XCTAssertEqual(BlockState.classify(live: contents, rendered: rendered), expected, text(contents))
        }
    }

    func testClassifiesEveryBlockStateThroughAnInjectedPath() throws {
        let rendered = try renderedWorkBlock()
        let shipped = try shippedHosts()
        let applied = try BlockSplice.splice(block: rendered, into: shipped)
        let refused = try file(bytes("# >>> hazmat:managed v1\n"))

        let appended = bytes(text(applied) + "# a note about hazmat:managed markers\n")
        let appendedLine = text(applied).reduce(1) { count, character in character == "\n" ? count + 1 : count }

        XCTAssertEqual(try LiveHostsFile(url: try file(shipped).url).state(rendered: rendered), .absent)
        XCTAssertEqual(try LiveHostsFile(url: try file(applied).url).state(rendered: rendered), .unchanged)
        XCTAssertEqual(
            try LiveHostsFile(url: try file(appended).url).state(rendered: rendered),
            .refused(.malformedMarker(line: appendedLine, text: "# a note about hazmat:managed markers"))
        )
        XCTAssertEqual(
            try LiveHostsFile(url: refused.url).state(rendered: rendered),
            .refused(.malformedMarker(line: 1, text: "# >>> hazmat:managed v1"))
        )
    }

    func testReadingReportsTheFileItFoundRatherThanACopy() throws {
        let rendered = try renderedWorkBlock()
        let shipped = try shippedHosts()
        let target = try file(shipped)

        XCTAssertEqual(try LiveHostsFile(url: target.url).state(rendered: rendered), .absent)
        try BlockSplice.splice(block: rendered, into: shipped).write(to: target.url)
        XCTAssertEqual(try LiveHostsFile(url: target.url).state(rendered: rendered), .unchanged)
    }

    // MARK: - 2.2 Drift

    func testReportsDriftRatherThanOverwritingIt() throws {
        let rendered = try renderedWorkBlock()
        let shipped = try shippedHosts()
        let target = try file(try BlockSplice.splice(block: rendered, into: shipped))
        let writer = RecordingWriter()
        let applier = HostsFileApplier(fileURL: target.url, writer: writer)
        let changed = BlockRenderer.render(
            try composition(fragments: [("base", "127.0.0.1\tchanged.example\n")], profile: "base\n")
        )
        let before = try target.snapshot()

        XCTAssertEqual(applier.apply(block: changed), .refused(.driftNotOverwritten))
        XCTAssertTrue(writer.writes.isEmpty)
        XCTAssertEqual(try target.snapshot(), before)
    }

    func testOverwritesDriftWhenTheCallerAsksAndReportsThatItDid() throws {
        let rendered = try renderedWorkBlock()
        let shipped = try shippedHosts()
        let target = try file(try BlockSplice.splice(block: rendered, into: shipped))
        let writer = RecordingWriter()
        let applier = HostsFileApplier(fileURL: target.url, writer: writer)
        let changed = BlockRenderer.render(
            try composition(fragments: [("base", "127.0.0.1\tchanged.example\n")], profile: "base\n")
        )

        XCTAssertEqual(applier.apply(block: changed, overwriteDrift: true), .applied(.replacedBlock(overwroteDrift: true)))

        let planned = try XCTUnwrap(writer.writes.last?.bytes)
        XCTAssertEqualBytes(try BlockSplice.strip(from: planned), shipped)
        let location = try XCTUnwrap(ManagedBlock.locate(in: planned))
        XCTAssertEqualBytes(Data(planned[location.range]), changed)
    }

    func testFirstApplyInstallsTheBlockBehindTheShippedBytes() throws {
        let rendered = try renderedWorkBlock()
        let shipped = try shippedHosts()
        let target = try file(shipped)
        let writer = RecordingWriter()
        let applier = HostsFileApplier(fileURL: target.url, writer: writer)

        XCTAssertEqual(applier.apply(block: rendered), .applied(.installedBlock))

        let planned = try XCTUnwrap(writer.writes.last?.bytes)
        XCTAssertEqualBytes(try BlockSplice.strip(from: planned), shipped)
        XCTAssertEqualBytes(Data(planned.suffix(rendered.count)), rendered)
        XCTAssertEqualBytes(try XCTUnwrap(writer.writes.last?.baseline), shipped)
    }

    // MARK: - 2.4 Planned bytes are verified before anything is written

    func testRefusesABlockThatIsNotOneWholeSupportedBlockAndLeavesTheFileAlone() throws {
        let rendered = try renderedWorkBlock()
        let shipped = try shippedHosts()
        let target = try file(shipped)
        let writer = RecordingWriter()
        let applier = HostsFileApplier(fileURL: target.url, writer: writer)
        let before = try target.snapshot()

        let refusals: [(Data, ApplyRefusal)] = [
            (
                bytes("127.0.0.1 localhost\n"),
                .unusableBlock(.block(.invalidBlock("it holds no managed block")))
            ),
            (
                bytes("# >>> hazmat:managed v2 >>>\n127.0.0.1 localhost\n# <<< hazmat:managed v2 <<<\n"),
                .unusableBlock(.block(.unsupportedVersion(found: 2, expected: 1)))
            ),
            (
                bytes("127.0.0.1 before\n") + rendered,
                .unusableBlock(.block(.invalidBlock("it carries content outside its markers")))
            ),
            (
                bytes("# >>> hazmat:managed v1 >>>\n127.0.0.1 localhost\n# <<< hazmat:managed v1 <<<\n# >>> hazmat:managed v1 >>>\n# <<< hazmat:managed v1 <<<\n"),
                .unusableBlock(.block(.multipleBlocks(firstLine: 1, secondLine: 4)))
            )
        ]

        for (block, expected) in refusals {
            let outcome = applier.apply(block: block)
            XCTAssertEqual(outcome, .refused(expected))
            XCTAssertTrue(outcome.description.contains("refused"), outcome.description)
        }
        XCTAssertTrue(writer.writes.isEmpty)
        XCTAssertEqual(try target.snapshot(), before)
    }

    func testRefusesPlannedBytesThatWouldChangeBytesOutsideTheBlock() throws {
        let rendered = try renderedWorkBlock()
        let live = try BlockSplice.splice(block: rendered, into: try shippedHosts())
        let tampered = bytes(text(live).replacingOccurrences(of: "127.0.0.1\tlocalhost\n", with: "10.0.0.9\tlocalhost\n"))

        XCTAssertEqual(PlanVerification.check(planned: live, live: live), .ok)
        XCTAssertEqual(
            PlanVerification.check(planned: try BlockSplice.splice(block: rendered, into: tampered), live: live),
            .bytesOutsideBlockChanged
        )
    }

    func testRefusesBytesOverTheSizeBound() throws {
        let oversized = Data(repeating: 0x61, count: PlannedBytes.sizeBound + 1)

        XCTAssertEqual(
            PlannedBytes.refusal(oversized),
            .oversized(actual: PlannedBytes.sizeBound + 1, bound: PlannedBytes.sizeBound)
        )

        let target = try file(try shippedHosts())
        let writer = RecordingWriter()
        let applier = HostsFileApplier(fileURL: target.url, writer: writer)
        // A well-formed block that is nonetheless over the bound.
        let stillRefused = applier.apply(
            block: bytes("# >>> hazmat:managed v1 >>>\n") + oversized + bytes("\n# <<< hazmat:managed v1 <<<\n"),
            position: .beforeFirstEntry
        )
        guard case .refused(.unusableBlock(.oversized)) = stillRefused else {
            return XCTFail("expected an oversized refusal, got \(stillRefused)")
        }
        XCTAssertTrue(writer.writes.isEmpty)
    }

    // MARK: - 2.5 Outcomes

    func testASecondApplyReportsNothingToDoAndDoesNotAdvanceTheModificationTime() throws {
        let rendered = try renderedWorkBlock()
        let target = try file(try shippedHosts())
        let writer = LocalWriter(target: target.url)
        let applier = HostsFileApplier(fileURL: target.url, writer: writer)

        XCTAssertEqual(applier.apply(block: rendered), .applied(.installedBlock))
        XCTAssertEqual(writer.writeCount, 1)
        let afterFirst = try target.snapshot()

        XCTAssertEqual(applier.apply(block: rendered), .nothingToDo)
        XCTAssertEqual(applier.apply(block: rendered), .nothingToDo)
        XCTAssertEqual(writer.writeCount, 1)
        XCTAssertEqual(try target.snapshot(), afterFirst)
    }

    func testOutcomeNamesTheCauseOfARefusalAndOfAFailure() throws {
        let rendered = try renderedWorkBlock()
        let target = try file(try shippedHosts())
        let writer = RecordingWriter()
        let applier = HostsFileApplier(fileURL: target.url, writer: writer)

        writer.result = .refused(reason: "the file changed since it was read")
        let refused = applier.apply(block: rendered)
        XCTAssertEqual(refused, .refused(.privileged("the file changed since it was read")))
        XCTAssertTrue(refused.description.contains("the file changed since it was read"))

        writer.result = .failed(reason: "the helper is not running")
        let failed = applier.apply(block: rendered)
        XCTAssertEqual(failed, .failed(reason: "the helper is not running"))
        XCTAssertTrue(failed.description.contains("the helper is not running"))
    }

    func testAnUnreadableLiveFileIsAFailureNotARefusal() throws {
        let target = try TemporaryHostsFile(try shippedHosts())
        let url = target.url
        target.remove()
        let applier = HostsFileApplier(fileURL: url, writer: RecordingWriter())

        guard case .failed(let reason) = applier.apply(block: try renderedWorkBlock()) else {
            return XCTFail("expected a failure for a missing file")
        }
        XCTAssertTrue(reason.contains("reading"), reason)
    }

    // MARK: - 2.6 Injected path and writer

    func testTheApplierWritesOnlyThroughTheInjectedWriter() throws {
        let rendered = try renderedWorkBlock()
        let shipped = try shippedHosts()
        let target = try file(shipped)
        let writer = RecordingWriter()
        let applier = HostsFileApplier(fileURL: target.url, writer: writer)
        let before = try target.snapshot()

        XCTAssertEqual(applier.apply(block: rendered), .applied(.installedBlock))

        XCTAssertEqual(writer.writes.count, 1)
        XCTAssertEqualBytes(writer.writes[0].baseline, shipped)
        XCTAssertEqualBytes(try BlockSplice.strip(from: writer.writes[0].bytes), shipped)
        XCTAssertEqual(try target.snapshot(), before, "a recording writer must leave the file alone")
    }

    // MARK: - Removal

    func testRemovingABlockRestoresThePreApplyBytes() throws {
        let rendered = try renderedWorkBlock()
        let shipped = try shippedHosts()
        let target = try file(try BlockSplice.splice(block: rendered, into: shipped))
        let writer = RecordingWriter()
        let applier = HostsFileApplier(fileURL: target.url, writer: writer)

        XCTAssertEqual(applier.removeBlock(), .applied(.removedBlock))
        XCTAssertEqual(writer.removals.count, 1)
        XCTAssertTrue(writer.writes.isEmpty)
        XCTAssertEqualBytes(writer.removals[0], try BlockSplice.splice(block: rendered, into: shipped))
    }

    func testRemovingABlockFromAFileThatHoldsNoneIsANoOp() throws {
        let shipped = try shippedHosts()
        let target = try file(shipped)
        let writer = RecordingWriter()
        let applier = HostsFileApplier(fileURL: target.url, writer: writer)
        let before = try target.snapshot()

        XCTAssertEqual(applier.removeBlock(), .nothingToDo)
        XCTAssertTrue(writer.removals.isEmpty)
        XCTAssertEqual(try target.snapshot(), before)
    }

    func testRemovalIsRefusedForADoubledMarkerSet() throws {
        let target = try file(
            bytes(
                "# >>> hazmat:managed v1 >>>\n"
                    + "# <<< hazmat:managed v1 <<<\n"
                    + "# >>> hazmat:managed v1 >>>\n"
                    + "# <<< hazmat:managed v1 <<<\n"
            )
        )
        let writer = RecordingWriter()
        let applier = HostsFileApplier(fileURL: target.url, writer: writer)

        XCTAssertEqual(
            applier.removeBlock(),
            .refused(.liveFile(.multipleBlocks(firstLine: 1, secondLine: 3)))
        )
        XCTAssertTrue(writer.removals.isEmpty)
    }

    func testRemoveThenApplyThenRemoveAgain() throws {
        let rendered = try renderedWorkBlock()
        let shipped = try shippedHosts()
        let target = try file(shipped)
        let writer = LocalWriter(target: target.url)
        let applier = HostsFileApplier(fileURL: target.url, writer: writer)

        XCTAssertEqual(applier.apply(block: rendered), .applied(.installedBlock))
        XCTAssertEqual(applier.removeBlock(), .applied(.removedBlock))
        XCTAssertEqualBytes(target.bytes, shipped)
        XCTAssertEqual(applier.apply(block: rendered), .applied(.installedBlock))
        XCTAssertEqual(applier.removeBlock(), .applied(.removedBlock))
        XCTAssertEqualBytes(target.bytes, shipped)
    }
}
