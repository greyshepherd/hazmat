import Foundation
import XCTest
@testable import HazmatPrivileged

final class AtomicWriteTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private let ownership = testOwnership()

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        try directory.write(bytes("original\n"))
    }

    override func tearDown() {
        directory.remove()
        directory = nil
        super.tearDown()
    }

    func testTheResultIsARegularFileWithTheDocumentedModeAndOwner() throws {
        try AtomicFileWriter(target: directory.target, owner: ownership).write(bytes("replaced\n"))

        XCTAssertEqualBytes(try directory.contents(), bytes("replaced\n"))

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.target.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeRegular)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o644)
        XCTAssertEqual((attributes[.ownerAccountID] as? NSNumber)?.uint32Value, ownership.uid)
        XCTAssertEqual((attributes[.groupOwnerAccountID] as? NSNumber)?.uint32Value, ownership.gid)

        // The daemon configures the system account; the suite is not root, so it
        // verifies the mechanism with its own uid.
        XCTAssertEqual(AtomicFileWriter.mode, 0o644)
        XCTAssertEqual(FileOwnership.system, FileOwnership(uid: 0, gid: 0))
        XCTAssertEqual(try directory.entries(), ["hosts"], "a temporary file was left behind")
    }

    func testRefusesAFileThatCarriesAnAccessControlList() throws {
        let writer = AtomicFileWriter(target: directory.target, owner: ownership)
        try setAccessControlList(at: directory.target)
        XCTAssertTrue(try writer.hasAccessControlList(at: directory.target.path))

        // A file that carries a list is refused rather than replaced.
        XCTAssertThrowsError(try writer.write(bytes("replaced\n"))) { error in
            guard case .accessControlList = error as? WriteFailure else {
                return XCTFail("expected an access-control refusal, got \(error)")
            }
        }
        XCTAssertEqualBytes(try directory.contents(), bytes("original\n"))
        XCTAssertEqual(try directory.entries(), ["hosts"])
    }

    func testAWriteLeavesNoAccessControlList() throws {
        let clean = try TemporaryDirectory()
        defer { clean.remove() }
        try clean.write(bytes("original\n"))

        let writer = AtomicFileWriter(target: clean.target, owner: ownership)
        try writer.write(bytes("replaced\n"))

        XCTAssertFalse(try writer.hasAccessControlList(at: clean.target.path))
        XCTAssertEqualBytes(try clean.contents(), bytes("replaced\n"))
    }

    func testAnInterruptedWriteLeavesThePreviousContentsInPlace() throws {
        var writer = AtomicFileWriter(target: directory.target, owner: ownership)
        writer.interruption = { throw WriteFailure.write("interrupted") }

        XCTAssertThrowsError(try writer.write(bytes("replaced\n")))

        XCTAssertEqualBytes(try directory.contents(), bytes("original\n"))
        XCTAssertEqual(try directory.entries(), ["hosts"], "a temporary file was left behind")
    }

    func testNoTemporaryFileSurvivesAnyFailurePath() throws {
        // Interrupted before the rename.
        var interrupted = AtomicFileWriter(target: directory.target, owner: ownership)
        interrupted.interruption = { throw WriteFailure.write("interrupted") }
        XCTAssertThrowsError(try interrupted.write(bytes("replaced\n")))
        XCTAssertEqual(try directory.entries(), ["hosts"])

        // Refused because the target carries a list.
        let acl = try TemporaryDirectory()
        defer { acl.remove() }
        try acl.write(bytes("original\n"))
        try setAccessControlList(at: acl.target)
        XCTAssertThrowsError(try AtomicFileWriter(target: acl.target, owner: ownership).write(bytes("replaced\n")))
        XCTAssertEqual(try acl.entries(), ["hosts"])

        // A target that cannot be replaced: its directory is read-only.
        let locked = try TemporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.url.path)
            locked.remove()
        }
        try locked.write(bytes("original\n"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.url.path)
        XCTAssertThrowsError(try AtomicFileWriter(target: locked.target, owner: ownership).write(bytes("replaced\n")))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.url.path)
        XCTAssertEqual(try locked.entries(), ["hosts"], "a temporary file was left behind")
        XCTAssertEqualBytes(try locked.contents(), bytes("original\n"))
    }

    func testAReaderDuringAWriteSeesOneCompleteVersion() throws {
        let old = Data(repeating: 0x41, count: 1 << 19)
        let new = Data(repeating: 0x42, count: 1 << 19)
        try directory.write(old)

        let log = ReadLog()
        let target = directory.target
        let reader = Thread {
            while !log.stop {
                guard let seen = try? Data(contentsOf: target) else { continue }
                log.record(seen == old || seen == new, seen == new)
            }
        }
        reader.start()

        var writer = AtomicFileWriter(target: target, owner: ownership)
        writer.interruption = { Thread.sleep(forTimeInterval: 0.05) }
        try writer.write(new)
        Thread.sleep(forTimeInterval: 0.05)
        log.stop = true

        XCTAssertGreaterThan(log.reads, 0, "the reader never ran")
        XCTAssertEqual(log.partial, 0, "a reader saw a partial file \(log.partial) times")
        XCTAssertGreaterThan(log.newVersions, 0, "the reader never saw the new file")
        XCTAssertEqualBytes(try directory.contents(), new)
    }

    func testReplacingAFileKeepsItsDirectoryEntriesClean() throws {
        let writer = AtomicFileWriter(target: directory.target, owner: ownership)
        for index in 0..<20 {
            try writer.write(bytes("replacement \(index)\n"))
        }
        XCTAssertEqual(try directory.entries(), ["hosts"])
        XCTAssertEqualBytes(try directory.contents(), bytes("replacement 19\n"))
    }
}

/// Reads and writes from the reader thread, so nothing races unsynchronised.
private final class ReadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stopping = false
    private var readCount = 0
    private var partialCount = 0
    private var newCount = 0

    var stop: Bool {
        get { lock.lock(); defer { lock.unlock() }; return stopping }
        set { lock.lock(); defer { lock.unlock() }; stopping = newValue }
    }

    var reads: Int {
        lock.lock(); defer { lock.unlock() }
        return readCount
    }

    var partial: Int {
        lock.lock(); defer { lock.unlock() }
        return partialCount
    }

    var newVersions: Int {
        lock.lock(); defer { lock.unlock() }
        return newCount
    }

    func record(_ complete: Bool, _ isNew: Bool) {
        lock.lock()
        defer { lock.unlock() }
        readCount += 1
        if !complete { partialCount += 1 }
        if isNew { newCount += 1 }
    }
}
