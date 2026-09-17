import Darwin
import Foundation
import XCTest

final class IsolationTests: XCTestCase {
    // MARK: - 1.3 The daemon imports no UI framework and no shell-out helper

    func testTheDaemonImportsNoUIFrameworkAndNoShellOutHelper() {
        let sources = sourceFiles(in: "Sources/HazmatDaemon")
        XCTAssertTrue(sources.contains { $0.0 == "main.swift" }, "the daemon target has no entry point")

        let allowed: Set<String> = ["Foundation", "HazmatCore", "HazmatPrivileged", "HazmatProtocol", "os"]
        for (file, source) in sources {
            let modules = imports(in: source)
            XCTAssertFalse(modules.isEmpty, "\(file) imports nothing")
            for module in modules where !allowed.contains(module) {
                XCTFail("\(file) imports \(module)")
            }
        }
    }

    func testTheWritePathImportsNothingOutsideTheSystemFrameworks() {
        let allowed: Set<String> = [
            "Foundation", "CryptoKit", "Security", "Darwin", "os",
            "HazmatCore", "HazmatPrivileged", "HazmatProtocol"
        ]
        for target in ["Sources/HazmatPrivileged", "Sources/HazmatProtocol"] {
            for (file, source) in sourceFiles(in: target) {
                for module in imports(in: source) where !allowed.contains(module) {
                    XCTFail("\(target)/\(file) imports \(module)")
                }
            }
        }
    }

    // MARK: - 9.1 and 9.2 The suite is isolation-safe

    func testNoTestNamesOrTouchesTheRealHostsFileOrTheRegistrationAPI() {
        let realHosts = "\"/etc" + "/hosts\""
        let needles = [realHosts, "SMAppService", "HelperRegistration()", "DaemonClient("]

        // IntegrationTests.swift is the exception and the point: it snapshots the
        // real file's bytes and modification time before and after the suite, and
        // reads it without writing.
        let exemptions: Set<String> = ["IsolationTests.swift", "IntegrationTests.swift"]

        for target in ["Tests/HazmatCoreTests", "Tests/HazmatPrivilegedTests", "Tests/HazmatAppSupportTests"] {
            let sources = sourceFiles(in: target).filter { !exemptions.contains($0.0) }
            XCTAssertFalse(sources.isEmpty, "\(target) has no sources")
            for (file, source) in sources {
                for needle in needles {
                    XCTAssertNil(
                        source.range(of: needle),
                        "\(target)/\(file) contains \(needle); the suite must not read or write the real hosts file, ask for approval, or reach the helper"
                    )
                }
            }
        }
    }

    func testTheSuiteRunsWithoutRoot() {
        XCTAssertNotEqual(getuid(), 0, "the suite must not run as root")
    }

    // MARK: - The one path the daemon builds

    func testTheDaemonBuildsItsTargetFromAConstant() {
        let source = sourceFiles(in: "Sources/HazmatDaemon")
            .first { $0.0 == "main.swift" }
            .map(\.1) ?? ""

        XCTAssertFalse(source.isEmpty)
        XCTAssertTrue(source.contains("DaemonTarget.hostsFile"), source)
        XCTAssertFalse(source.contains("environment"), source)
        XCTAssertFalse(source.contains("CommandLine"), source)
        XCTAssertFalse(source.contains("arguments"), source)
    }
}

private func imports(in source: String) -> [String] {
    source
        .split(separator: "\n")
        .compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("import ") else { return nil }
            return String(trimmed.dropFirst("import ".count)).trimmingCharacters(in: .whitespaces)
        }
}
