import Foundation
import XCTest

/// The release tooling, exercised without a network, a certificate, or a key: the
/// pin that keeps a distribution honest, the entry that carries a release to an
/// installed copy, and the two refusals that keep a publish from going out twice
/// or from going out at all without a token.
final class ReleaseToolingTests: XCTestCase {
    private struct Outcome {
        let status: Int32
        let output: String
    }

    private func run(_ script: String, _ arguments: [String]) throws -> Outcome {
        let process = Process()
        process.executableURL = repositoryRoot().appendingPathComponent("Scripts/\(script)")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Outcome(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    private func workingDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hazmat-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func write(_ contents: String, to url: URL, executable: Bool = false) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    /// A tools directory whose signing tool answers with a fixed signature, so the
    /// entry can be checked without a keychain item or the real distribution.
    private func stubbedTools(signature: String = "c2lnbmF0dXJl+/=", status: Int32 = 0) throws -> URL {
        let tools = try workingDirectory("tools")
        let script = status == 0
            ? "#!/bin/bash\nprintf '%s\\n' '\(signature)'\n"
            : "#!/bin/bash\nprintf 'ERROR! Signing key not found for account ed25519.\\n'\nexit \(status)\n"
        try write(script, to: tools.appendingPathComponent("sign_update"), executable: true)
        return tools
    }

    // MARK: - The pin

    func testThePinnedDistributionNamesTheVersionThePackageResolves() throws {
        let pin = try JSONSerialization.jsonObject(
            with: try Data(contentsOf: repositoryRoot().appendingPathComponent("release/sparkle.json"))
        ) as? [String: Any]
        let version = try XCTUnwrap(pin?["version"] as? String, "the pin names no version")
        let url = try XCTUnwrap(URL(string: try XCTUnwrap(pin?["url"] as? String, "the pin names no address")))
        let checksum = try XCTUnwrap(pin?["sha256"] as? String, "the pin names no checksum")

        XCTAssertTrue(
            checksum.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
            "the checksum is not a SHA-256 digest: \(checksum)"
        )
        XCTAssertTrue(url.absoluteString.contains(version), "the address does not name the pinned version")

        // The framework the bundle embeds comes from the package manifest, and the
        // tools that sign a release come from this pin. One version, or a release
        // is signed by a tool that does not match the framework it ships.
        let manifest = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Package.swift"), encoding: .utf8
        )
        let resolved = try XCTUnwrap(
            manifest.range(of: #"from: "(\d+\.\d+\.\d+)""#, options: .regularExpression)
                .map { String(manifest[$0]) },
            "the package manifest pins no framework version"
        )
        XCTAssertEqual(
            resolved.replacingOccurrences(of: "from: \"", with: "").replacingOccurrences(of: "\"", with: ""),
            version,
            "the pinned distribution and the framework the package resolves disagree"
        )
    }

    func testATamperedDistributionIsRefusedAndDiscarded() throws {
        let cache = try workingDirectory("cache")
        let archive = cache.appendingPathComponent("9.9.9/Sparkle-9.9.9.tar.xz")
        try FileManager.default.createDirectory(
            at: archive.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // The archive is already cached, so nothing is fetched: the refusal is
        // about the bytes on disk, not about the download.
        try write("not the pinned distribution", to: archive)

        let pin = cache.appendingPathComponent("pin.json")
        try write(
            """
            {"version": "9.9.9", "url": "https://example.invalid/Sparkle-9.9.9.tar.xz", "sha256": "\(String(repeating: "0", count: 64))"}
            """,
            to: pin
        )

        let refused = try run("sparkle-tools.sh", ["--pin", pin.path, "--cache", cache.path])

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("not the pinned one"), refused.output)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: archive.path),
            "a distribution that is not the pinned one must not be left to be used"
        )
    }

    func testAPinThatNamesNoChecksumIsRefused() throws {
        let directory = try workingDirectory("pin")
        let pin = directory.appendingPathComponent("pin.json")
        try write(#"{"version": "9.9.9", "url": "https://example.invalid/Sparkle-9.9.9.tar.xz"}"#, to: pin)

        let refused = try run("sparkle-tools.sh", ["--pin", pin.path, "--cache", directory.path])

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("no checksum"), refused.output)
    }

    // MARK: - The feed entry

    private func entry(
        for archive: URL,
        tools: URL,
        notes: String? = "https://github.com/greyshepherd/hazmat/releases/tag/v1.0.0"
    ) throws -> XMLElement {
        var arguments = [
            "--archive", archive.path,
            "--url", "https://github.com/greyshepherd/hazmat/releases/download/v1.0.0/\(archive.lastPathComponent)",
            "--tools", tools.path,
            "--date", "Fri, 18 Sep 2026 12:00:00 +0000"
        ]
        if let notes { arguments += ["--notes", notes] }

        let printed = try run("appcast-entry.sh", arguments)
        XCTAssertEqual(printed.status, 0, printed.output)

        let document = try XMLDocument(xmlString: printed.output)
        return try XCTUnwrap(document.rootElement(), "the entry is not XML")
    }

    private func value(
        of element: String,
        in entry: XMLElement,
        namespace: String? = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    ) throws -> String {
        let nodes = try entry.nodes(forXPath: "*[local-name()='\(element)']")
        let node = try XCTUnwrap(nodes.first as? XMLElement, "the entry states no \(element)")
        XCTAssertEqual(node.uri, namespace, "\(element) is not in the namespace the framework reads")
        return try XCTUnwrap(node.stringValue, "\(element) is empty")
    }

    func testAFeedEntryStatesEverythingTheAppDecidesOn() throws {
        let directory = try workingDirectory("entry")
        let archive = directory.appendingPathComponent("Hazmat-1.0.0.dmg")
        let bytes = "a disk image"
        try write(bytes, to: archive)

        let item = try entry(for: archive, tools: try stubbedTools())
        let config = try releaseConfiguration()
        let build = String(describing: try XCTUnwrap(config["buildNumber"] as? Int))

        XCTAssertEqual(try value(of: "version", in: item), build)
        XCTAssertEqual(try value(of: "shortVersionString", in: item), config["shortVersion"] as? String)
        XCTAssertEqual(try value(of: "minimumSystemVersion", in: item), "15.0")
        XCTAssertEqual(try value(of: "hardwareRequirements", in: item), "arm64", "the product is Apple silicon only")
        XCTAssertEqual(
            try value(of: "pubDate", in: item, namespace: nil), "Fri, 18 Sep 2026 12:00:00 +0000"
        )
        XCTAssertTrue(
            try value(of: "releaseNotesLink", in: item).contains("releases/tag/"),
            "the entry must link the notes the release carries"
        )

        let enclosure = try XCTUnwrap(
            item.elements(forName: "enclosure").first, "the entry names no archive"
        )
        XCTAssertEqual(enclosure.attribute(forName: "length")?.stringValue, String(bytes.utf8.count))
        XCTAssertEqual(enclosure.attribute(forName: "url")?.stringValue, 
            "https://github.com/greyshepherd/hazmat/releases/download/v1.0.0/Hazmat-1.0.0.dmg")
        XCTAssertEqual(
            enclosure.attribute(forName: "sparkle:edSignature")?.stringValue, "c2lnbmF0dXJl+/=",
            "the entry must carry the signature over the archive's bytes"
        )
    }

    func testAnArchiveThatCannotBeSignedIsRefused() throws {
        let directory = try workingDirectory("unsigned")
        let archive = directory.appendingPathComponent("Hazmat-1.0.0.dmg")
        try write("a disk image", to: archive)

        let refused = try run("appcast-entry.sh", [
            "--archive", archive.path,
            "--url", "https://github.com/greyshepherd/hazmat/releases/download/v1.0.0/Hazmat-1.0.0.dmg",
            "--tools", try stubbedTools(status: 1).path
        ])

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("could not be signed"), refused.output)
        XCTAssertTrue(refused.output.contains("Signing key not found"), refused.output)
    }

    func testAnArchiveAddressThatIsNotHTTPSIsRefused() throws {
        let directory = try workingDirectory("plain")
        let archive = directory.appendingPathComponent("Hazmat-1.0.0.dmg")
        try write("a disk image", to: archive)

        let refused = try run("appcast-entry.sh", [
            "--archive", archive.path,
            "--url", "http://example.invalid/Hazmat-1.0.0.dmg",
            "--tools", try stubbedTools().path
        ])

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("not HTTPS"), refused.output)
    }

    // MARK: - Publishing

    private func publishedFeed(carrying builds: [Int]) throws -> URL {
        let directory = try workingDirectory("published")
        let feed = directory.appendingPathComponent("appcast.xml")
        let items = builds.map { "<item><sparkle:version>\($0)</sparkle:version></item>" }.joined(separator: "\n")
        try write(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <title>Hazmat</title>
            \(items)
              </channel>
            </rss>
            """,
            to: feed
        )
        return feed
    }

    private func artifact() throws -> URL {
        let directory = try workingDirectory("artifact")
        let url = directory.appendingPathComponent("Hazmat-1.0.0.dmg")
        try write("a disk image", to: url)
        return url
    }

    func testPublishingRefusesABuildNumberTheFeedAlreadyCarries() throws {
        let refused = try run("publish.sh", [
            "--artifact", try artifact().path,
            "--published", try publishedFeed(carrying: [1, 4]).path,
            "--dry-run"
        ])

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("not greater than 4"), refused.output)
    }

    func testPublishingRefusesABuildNumberSmallerThanThePublishedOne() throws {
        let refused = try run("publish.sh", [
            "--artifact", try artifact().path,
            "--published", try publishedFeed(carrying: [7]).path,
            "--dry-run"
        ])

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("not greater than 7"), refused.output)
    }

    func testPublishingWithoutATokenStopsBeforeUploadingAnything() throws {
        let refused = try run("publish.sh", [
            "--artifact", try artifact().path,
            "--published", try publishedFeed(carrying: []).path
        ])

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("HAZMAT_GITHUB_TOKEN"), refused.output)
        XCTAssertTrue(refused.output.contains("no GitHub token"), refused.output)
    }

    func testARehearsalReportsWhatWouldBePublished() throws {
        let rehearsed = try run("publish.sh", [
            "--artifact", try artifact().path,
            "--published", try publishedFeed(carrying: []).path,
            "--dry-run"
        ])

        XCTAssertEqual(rehearsed.status, 0, rehearsed.output)
        let config = try releaseConfiguration()
        let update = try XCTUnwrap(config["update"] as? [String: Any])
        XCTAssertTrue(rehearsed.output.contains(update["releaseRepo"] as? String ?? "?"), rehearsed.output)
        XCTAssertTrue(rehearsed.output.contains("v\(config["shortVersion"] as? String ?? "?")"), rehearsed.output)
        XCTAssertTrue(rehearsed.output.contains("published:  nothing"), rehearsed.output)
    }

    // MARK: - The feed itself

    func testTheFeedIsAWellFormedChannelWithNoSecondCopyOfTheAddress() throws {
        let url = repositoryRoot().appendingPathComponent("docs/appcast.xml")
        let document = try XMLDocument(contentsOf: url)
        XCTAssertEqual(document.rootElement()?.name, "rss")
        XCTAssertEqual(
            try document.nodes(forXPath: "/*[local-name()='rss']/*[local-name()='channel']/*[local-name()='title']")
                .first?.stringValue,
            "Hazmat"
        )

        let text = try String(contentsOf: url, encoding: .utf8)
        let config = try releaseConfiguration()
        let update = try XCTUnwrap(config["update"] as? [String: Any])
        let host = try XCTUnwrap(URL(string: try XCTUnwrap(update["feedURL"] as? String))?.host)
        XCTAssertNil(
            text.range(of: host),
            "the feed repeats the address the release configuration owns"
        )
    }
}
