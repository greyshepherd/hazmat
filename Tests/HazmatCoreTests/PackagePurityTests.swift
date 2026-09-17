import Darwin
import Foundation
import XCTest

/// The core is plain Swift: no UI framework, no privileged framework, and
/// nothing that only works as root.
final class PackagePurityTests: XCTestCase {
    func testLibraryTargetImportsNothingOutsideFoundation() throws {
        let sources = try librarySources()
        XCTAssertFalse(sources.isEmpty, "the library target has no sources")

        var offending: [String] = []
        for (file, source) in sources {
            for line in source.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                let module = trimmed.dropFirst("import ".count).trimmingCharacters(in: .whitespaces)
                if module != "Foundation" {
                    offending.append("\(file): import \(module)")
                }
            }
        }
        XCTAssertEqual(offending, [], "the pure core may not import these")
    }

    func testLibrarySourcesArePresent() throws {
        let names = try librarySources().map(\.0)
        XCTAssertTrue(names.contains("Fragment.swift"), "sources: \(names)")
    }

    func testSuiteRunsWithoutRoot() {
        XCTAssertNotEqual(getuid(), 0, "the suite must run as a non-root user")
    }

    private func librarySources() throws -> [(String, String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/HazmatCore")
        return try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }
}
