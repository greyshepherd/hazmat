import HazmatProtocol
import XCTest

/// The assembler takes the identity from the code and the version from the
/// release configuration. These check that it reports what those say, and that
/// it refuses a release it cannot complete — all without building anything.
final class AssemblerTests: XCTestCase {
    func testTheAssemblerReportsTheIdentityTheCodeDeclares() throws {
        let printed = try printedConfiguration(named: "print-config")

        XCTAssertEqual(printed["bundleIdentifier"], HazmatIdentity.bundleIdentifier)
        XCTAssertEqual(printed["appExecutable"], HazmatIdentity.appExecutableName)
        XCTAssertEqual(printed["daemonExecutable"], HazmatIdentity.daemonExecutableName)
        XCTAssertEqual(printed["daemonLabel"], HazmatIdentity.daemonLabel)
        XCTAssertEqual(printed["machServiceName"], HazmatIdentity.machServiceName)
        XCTAssertEqual(printed["daemonPlistName"], HazmatIdentity.daemonPlistName)
        XCTAssertEqual(printed["iconName"], "Hazmat")
        XCTAssertEqual(printed["minimumSystemVersion"], "15.0")
    }

    func testTheAssemblerReportsTheVersionTheConfigurationNames() throws {
        let printed = try printedConfiguration(named: "print-config")
        let config = try releaseConfiguration()
        let feed = try XCTUnwrap((config["update"] as? [String: Any])?["feedURL"] as? String)

        XCTAssertEqual(printed["shortVersion"], config["shortVersion"] as? String)
        XCTAssertEqual(printed["buildNumber"], String(describing: try XCTUnwrap(config["buildNumber"] as? Int)))
        XCTAssertEqual(printed["feedURL"], feed)
    }

    func testAReleaseWithoutAFeedIsRefused() throws {
        let refused = try run(arguments: [
            "--configuration", "release",
            "--config", try writeConfiguration(feedURL: "", publicKey: "not-a-key"),
            "--output", "/tmp/hazmat-refused.app"
        ])

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("feed"), refused.output)
    }

    func testAReleaseWithoutTheSigningKeyIsRefused() throws {
        let refused = try run(arguments: [
            "--configuration", "release",
            "--config", try writeConfiguration(feedURL: "https://feed.invalid/appcast.xml", publicKey: ""),
            "--output", "/tmp/hazmat-refused.app"
        ])

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("signing key"), refused.output)
    }

    func testAnUnknownConfigurationIsRefused() throws {
        let refused = try run(arguments: ["--configuration", "benchmark"])

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("debug or release"), refused.output)
    }

    // MARK: - Running the assembler without building

    private struct Outcome {
        let status: Int32
        let output: String
    }

    private func run(arguments: [String]) throws -> Outcome {
        let process = Process()
        process.executableURL = repositoryRoot().appendingPathComponent("Scripts/assemble-bundle.sh")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Outcome(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    private func printedConfiguration(named label: String, arguments: [String] = []) throws -> [String: String] {
        let outcome = try run(arguments: ["--print-config"] + arguments)
        XCTAssertEqual(outcome.status, 0, "\(label) failed: \(outcome.output)")

        var printed: [String: String] = [:]
        for line in outcome.output.split(separator: "\n") {
            guard let separator = line.firstIndex(of: "=") else { continue }
            printed[String(line[line.startIndex..<separator])] = String(line[line.index(after: separator)...])
        }
        return printed
    }

    /// The checked-in configuration with only the feed and its key changed, so the
    /// test carries no second copy of an identity, a version, or a bucket.
    private func writeConfiguration(feedURL: String, publicKey: String) throws -> String {
        var config = try releaseConfiguration()
        var update = try XCTUnwrap(config["update"] as? [String: Any])
        update["feedURL"] = feedURL
        update["publicKey"] = publicKey
        config["update"] = update

        let path = "/tmp/hazmat-assembler-test-\(feedURL.isEmpty ? "no-feed" : "feed").json"
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted])
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }
}
