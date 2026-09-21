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
        try run(
            repositoryRoot().appendingPathComponent("Scripts/\(script)"),
            arguments,
            environment: [:]
        )
    }

    private func run(
        _ script: URL,
        _ arguments: [String],
        environment: [String: String]
    ) throws -> Outcome {
        let process = Process()
        process.executableURL = script
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Outcome(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL?) throws -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = directory.map { ["-C", $0.path] + arguments } ?? arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "GIT_AUTHOR_NAME": "rehearsal",
            "GIT_AUTHOR_EMAIL": "rehearsal@invalid",
            "GIT_COMMITTER_NAME": "rehearsal",
            "GIT_COMMITTER_EMAIL": "rehearsal@invalid",
        ]) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let outcome = Outcome(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        XCTAssertEqual(outcome.status, 0, "git \(arguments.joined(separator: " ")): \(outcome.output)")
        return outcome
    }

    /// A rehearsal of the repository: a bare origin and a clone of it, with the
    /// working tree's publish script committed on top. The clone is the root the
    /// script resolves, so pushing a tag lands in the throwaway origin rather than
    /// in the repository this suite is running against.
    ///
    /// The changelog's section for the version being cut carries
    /// `changelogSection`, so a release page that would carry notes is exercised
    /// beside one that has no section to carry.
    private func rehearsal(
        cutting version: String,
        build: Int,
        changelogSection: String? = "A rehearsal."
    ) throws -> (clone: URL, origin: URL) {
        let scratch = try workingDirectory("rehearsal")
        let origin = scratch.appendingPathComponent("origin.git")
        try git(["clone", "--quiet", "--local", "--bare", repositoryRoot().path, origin.path], in: nil)
        let clone = scratch.appendingPathComponent("clone")
        try git(["clone", "--quiet", "--local", origin.path, clone.path], in: nil)

        // The working tree's script, not the committed one, so this cannot pass
        // against a version of the script that is not the one being changed.
        let script = try Data(contentsOf: repositoryRoot().appendingPathComponent("Scripts/publish.sh"))
        try script.write(to: clone.appendingPathComponent("Scripts/publish.sh"))

        let config = try JSONSerialization.jsonObject(
            with: try Data(contentsOf: clone.appendingPathComponent("release/config.json"))
        ) as? [String: Any] ?? [:]
        var rewritten = config
        rewritten["shortVersion"] = version
        rewritten["buildNumber"] = build
        try JSONSerialization.data(withJSONObject: rewritten, options: [.prettyPrinted])
            .write(to: clone.appendingPathComponent("release/config.json"))

        if let changelogSection {
            // Appended, so the section for this version is the last one in the file
            // and runs to the end of it.
            let file = clone.appendingPathComponent("CHANGELOG.md")
            let existing = try String(contentsOf: file, encoding: .utf8)
            try write("\(existing)\n## \(version) — 2026-09-18\n\n\(changelogSection)\n", to: file)
        }

        try git(["add", "-A"], in: clone)
        try git(["commit", "--quiet", "-m", "rehearsal: cut \(version)"], in: clone)
        return (clone, origin)
    }

    private func head(of repository: URL) throws -> String {
        try git(["rev-parse", "HEAD"], in: repository).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tagTarget(_ tag: String, in repository: URL) throws -> String {
        try git(["rev-parse", "\(tag)^{commit}"], in: repository).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func publishedFixture() throws -> URL {
        let directory = try workingDirectory("published-empty")
        let feed = directory.appendingPathComponent("appcast.xml")
        try write(
            "<?xml version=\"1.0\"?><rss><channel><title>Hazmat</title></channel></rss>\n",
            to: feed
        )
        return feed
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
        let build = try XCTUnwrap(try releaseConfiguration()["buildNumber"] as? Int, "buildNumber")
        let refused = try run("publish.sh", [
            "--artifact", try artifact().path,
            "--published", try publishedFeed(carrying: [1, build]).path,
            "--dry-run"
        ])

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("not greater than \(build)"), refused.output)
    }

    func testPublishingRefusesABuildNumberSmallerThanThePublishedOne() throws {
        let build = try XCTUnwrap(try releaseConfiguration()["buildNumber"] as? Int, "buildNumber")
        let refused = try run("publish.sh", [
            "--artifact", try artifact().path,
            "--published", try publishedFeed(carrying: [build + 3]).path,
            "--dry-run"
        ])

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("not greater than \(build + 3)"), refused.output)
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

    // MARK: - The release page carries the changelog

    func testAPublishWithoutAChangelogSectionIsRefusedBeforeAnythingIsTagged() throws {
        let (clone, origin) = try rehearsal(cutting: "9.9.9", build: 9, changelogSection: nil)

        let refused = try run(
            clone.appendingPathComponent("Scripts/publish.sh"),
            ["--artifact", try artifact().path, "--published", try publishedFixture().path],
            environment: ["HAZMAT_GITHUB_TOKEN": "not-a-real-token"]
        )

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("CHANGELOG.md"), refused.output)
        XCTAssertTrue(refused.output.contains("9.9.9"), refused.output)
        XCTAssertEqual(
            try git(["tag", "--list", "v9.9.9"], in: origin).output
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "",
            "a release with no notes must not be tagged"
        )
    }

    func testAPublishWithAnEmptyChangelogSectionIsRefused() throws {
        let (clone, origin) = try rehearsal(cutting: "9.9.9", build: 9, changelogSection: "")

        let refused = try run(
            clone.appendingPathComponent("Scripts/publish.sh"),
            ["--artifact", try artifact().path, "--published", try publishedFixture().path],
            environment: ["HAZMAT_GITHUB_TOKEN": "not-a-real-token"]
        )

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("is empty"), refused.output)
        XCTAssertEqual(
            try git(["tag", "--list", "v9.9.9"], in: origin).output
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "",
            "a release with no notes must not be tagged"
        )
    }

    func testARehearsalNamesTheChangelogSectionForTheVersionItWouldPublish() throws {
        let rehearsed = try run("publish.sh", [
            "--artifact", try artifact().path,
            "--published", try publishedFeed(carrying: []).path,
            "--dry-run"
        ])

        XCTAssertEqual(rehearsed.status, 0, rehearsed.output)
        let config = try releaseConfiguration()
        let version = try XCTUnwrap(config["shortVersion"] as? String, "the configuration names no short version")
        XCTAssertTrue(
            rehearsed.output.contains("CHANGELOG.md (the \(version) section)"),
            "the release body must be the changelog's section for \(version): \(rehearsed.output)"
        )
    }

    // MARK: - The tag names the commit the release was cut from

    /// Left to the release host, the tag lands on whatever the default branch's
    /// head happens to be, which need not be the tree the artifact was built from —
    /// so the tag named a commit that could not reproduce the release.
    func testAPublishTagsTheCommitItPublishes() throws {
        let (clone, origin) = try rehearsal(cutting: "9.9.9", build: 9)
        let published = try git(["rev-parse", "HEAD"], in: clone).output
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let outcome = try run(
            clone.appendingPathComponent("Scripts/publish.sh"),
            [
                "--artifact", try artifact().path,
                "--published", try publishedFixture().path
            ],
            environment: ["HAZMAT_GITHUB_TOKEN": "not-a-real-token"]
        )

        XCTAssertTrue(outcome.output.contains("tagging v9.9.9"), outcome.output)
        XCTAssertEqual(try tagTarget("v9.9.9", in: origin), published, "the tag must name the commit being published")
        XCTAssertEqual(
            try git(["cat-file", "-t", "v9.9.9"], in: origin).output.trimmingCharacters(in: .whitespacesAndNewlines),
            "tag",
            "the tag carries a message rather than pointing at a commit unnamed"
        )
        // The token is a placeholder, so the run stops at the release host — which
        // is after the tag, and is what this test is not about.
        XCTAssertNotEqual(outcome.status, 0)
    }

    func testAPublishRefusesATagThatNamesAnotherCommit() throws {
        let (clone, origin) = try rehearsal(cutting: "9.9.9", build: 9)
        let published = try git(["rev-parse", "HEAD"], in: clone).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let earlier = try git(["rev-parse", "HEAD~1"], in: clone).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try git(["tag", "--annotate", "v9.9.9", "--message", "a tag on the wrong commit", earlier], in: clone)
        try git(["push", "--quiet", "origin", "refs/tags/v9.9.9"], in: clone)

        let refused = try run(
            clone.appendingPathComponent("Scripts/publish.sh"),
            [
                "--artifact", try artifact().path,
                "--published", try publishedFixture().path
            ],
            environment: ["HAZMAT_GITHUB_TOKEN": "not-a-real-token"]
        )

        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.output.contains("already names"), refused.output)
        XCTAssertTrue(refused.output.contains("never moved"), refused.output)
        XCTAssertEqual(try tagTarget("v9.9.9", in: origin), earlier, "a published tag is left where it is")
        XCTAssertNotEqual(try tagTarget("v9.9.9", in: origin), published)
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

    // MARK: - Every script's help is its header

    /// A hardcoded line range stops naming the end of a header the moment a line is
    /// added to it, and the truncation is silent: four of these printed half a
    /// sentence before the ranges were replaced.
    func testEveryScriptHelpCarriesItsWholeHeader() throws {
        let directory = repositoryRoot().appendingPathComponent("Scripts")
        let scripts = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".sh") }
            .sorted()
        XCTAssertGreaterThan(scripts.count, 3, "the scan found almost nothing to check")

        for script in scripts {
            let source = try String(contentsOf: directory.appendingPathComponent(script), encoding: .utf8)
            let header = source.components(separatedBy: "\n").dropFirst(2).prefix { $0.hasPrefix("#") }
            let lastLine = try XCTUnwrap(header.last, "\(script) carries no header")
            let line = lastLine.replacingOccurrences(of: "^# ?", with: "", options: .regularExpression)

            let printed = try run(script, ["--help"])
            XCTAssertEqual(printed.status, 0, "\(script) --help: \(printed.output)")
            XCTAssertTrue(
                printed.output.contains(line),
                "\(script) --help stops before its header ends, missing: \(line)"
            )
        }
    }
}
