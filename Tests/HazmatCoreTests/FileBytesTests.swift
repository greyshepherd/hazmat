import Foundation
import XCTest
@testable import HazmatCore

/// A file's bytes, read whole. A large file is read into pages the kernel
/// takes back the moment the reading lets go of them, rather than into a
/// malloc block that stays with the process after it is freed.
final class FileBytesTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hazmat-filebytes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(_ name: String, holding data: Data) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testReadsAnEmptyASmallAndALargeFileAsTheirBytes() throws {
        let empty = try file("empty", holding: Data())
        let small = try file("small", holding: Data("127.0.0.1 localhost\n".utf8))
        let large = try file("large", holding: Data(repeating: 0x61, count: FileBytes.pageThreshold * 3 + 17))

        for url in [empty, small, large] {
            XCTAssertEqualBytes(try FileBytes.read(url), try Data(contentsOf: url), url.lastPathComponent)
        }
    }

    func testAFileExactlyAtTheThresholdReadsWhole() throws {
        let url = try file("edge", holding: Data((0..<FileBytes.pageThreshold).map { UInt8(truncatingIfNeeded: $0) }))

        XCTAssertEqualBytes(try FileBytes.read(url), try Data(contentsOf: url))
    }

    func testALargeFileIsNotHeldInMalloc() throws {
        let url = try file("large", holding: Data(repeating: 0x62, count: FileBytes.pageThreshold * 2))

        let data = try FileBytes.read(url)

        let inMalloc = data.withUnsafeBytes { buffer -> Bool in
            malloc_size(buffer.baseAddress) != 0
        }
        XCTAssertFalse(inMalloc, "a large file's bytes belong to the kernel, not to malloc")
    }

    func testAMissingFileThrows() {
        XCTAssertThrowsError(try FileBytes.read(directory.appendingPathComponent("absent")))
    }

    func testAFileThatGrewWhileBeingReadIsReadWhole() throws {
        // The size is asked before the bytes; a file larger than its size said
        // is read again rather than truncated to what was expected.
        let url = try file("growing", holding: Data(repeating: 0x63, count: FileBytes.pageThreshold * 2))
        let grown = Data(repeating: 0x64, count: FileBytes.pageThreshold * 2 + 100)

        let data = try FileBytes.read(url, sizing: { _ in
            try grown.write(to: url)
            return FileBytes.pageThreshold * 2
        })

        XCTAssertEqualBytes(data, grown)
    }
}
