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

    func testThePrivilegedWriterAsksForExactlyTwoThings() throws {
        let source = try String(contentsOf: repositoryRoot().appendingPathComponent("Sources/HazmatCore/PrivilegedWriter.swift"), encoding: .utf8)

        XCTAssertEqual(source.components(separatedBy: "func ").count - 1, 2, source)
        XCTAssertTrue(source.contains("func write(bytes: Data, baseline: Data)"), source)
        XCTAssertTrue(source.contains("func removeBlock(baseline: Data)"), source)
    }

    func testTheXPCInterfaceCarriesNoMethodThisChangeAdded() throws {
        let source = try String(contentsOf: repositoryRoot().appendingPathComponent("Sources/HazmatProtocol/HazmatIdentity.swift"), encoding: .utf8)
        let body = try XCTUnwrap(
            source.components(separatedBy: "protocol HazmatDaemonXPC {").last?.components(separatedBy: "\n}").first
        )

        XCTAssertEqual(body.components(separatedBy: "func ").count - 1, 2, body)
        XCTAssertTrue(body.contains("func writeFileBytes("), body)
        XCTAssertTrue(body.contains("func removeManagedBlock("), body)
    }

    func testThePrivilegedSideStillKnowsNothingAboutProfilesOrTheMenu() throws {
        let sources = try sources(in: "Sources/HazmatPrivileged")
        XCTAssertFalse(sources.isEmpty, "the privileged target has no sources")

        for (file, source) in sources {
            for needle in ["ProfileID", "MenuPresentation", "ActiveProfile", "Activation", "ShellModel"] {
                XCTAssertNil(source.range(of: needle), "\(file) contains \(needle)")
            }
        }
    }

    private func librarySources() throws -> [(String, String)] {
        try sources(in: "Sources/HazmatCore")
    }

    private func sources(in relativePath: String) throws -> [(String, String)] {
        let root = repositoryRoot().appendingPathComponent(relativePath)
        return try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
