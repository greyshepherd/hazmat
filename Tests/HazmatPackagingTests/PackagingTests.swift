import XCTest

/// The packaging facts a bundle depends on: the assets it ships, the one place a
/// version is stated, and the licence text that travels with a framework.
final class PackagingTests: XCTestCase {
    private var assets: URL { repositoryRoot().appendingPathComponent("Assets") }

    func testTheMenuBarTemplateIsBlackPlusAlphaAtBothSizes() throws {
        for (name, size) in [("menu-bar-template", 22), ("menu-bar-template@2x", 44)] {
            let image = try decodeImage(at: assets.appendingPathComponent("\(name).png"))
            XCTAssertEqual(image.width, size, name)
            XCTAssertEqual(image.height, size, name)

            for y in 0..<image.height {
                for x in 0..<image.width {
                    let pixel = image.pixel(x: x, y: y)
                    guard pixel.alpha > 0 else { continue }
                    // The mark is black plus alpha: the shape lives in the alpha
                    // channel and the colour is neutral, which is what lets macOS
                    // tint it. A pixel that carried colour would survive the
                    // premultiplication as an unequal triple once scaled back.
                    let premultiplied = [pixel.red, pixel.green, pixel.blue].map { Int($0) }
                    let straight = premultiplied.map { $0 * 255 / Int(pixel.alpha) }
                    XCTAssertLessThanOrEqual(
                        straight.max()! - straight.min()!, 2,
                        "\(name) pixel \(x),\(y) carries colour"
                    )
                    XCTAssertLessThanOrEqual(premultiplied.max()!, Int(pixel.alpha), "\(name) pixel \(x),\(y)")
                }
            }

            XCTAssertGreaterThan(
                image.visiblePixels, image.width * image.height / 4,
                "\(name) is nearly empty, so the check above is vacuous"
            )
        }
    }

    func testTheAppIconIsACompleteIconFile() throws {
        let icon = try IconFile.read(at: assets.appendingPathComponent("Hazmat.icns"))
        XCTAssertEqual(icon.declaredLength, icon.actualLength, "the icon's declared length is wrong")
        for type in ["ic07", "ic08", "ic09", "ic10"] {
            XCTAssertTrue(icon.types.contains(type), "the icon has no \(type) representation: \(icon.types)")
        }
        XCTAssertFalse(
            icon.types.filter { ["icp4", "icp5", "ic11", "ic12"].contains($0) }.isEmpty,
            "the icon has no small representation: \(icon.types)"
        )
    }

    func testTheReleaseConfigurationNamesOneVersionAndOneFeed() throws {
        let config = try releaseConfiguration()
        let shortVersion = try XCTUnwrap(config["shortVersion"] as? String, "shortVersion")
        XCTAssertNotNil(
            shortVersion.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression),
            "shortVersion is not major.minor.patch: \(shortVersion)"
        )
        XCTAssertGreaterThan(try XCTUnwrap(config["buildNumber"] as? Int, "buildNumber"), 0)
        XCTAssertFalse(try XCTUnwrap(config["teamIdentifier"] as? String, "teamIdentifier").isEmpty)

        let update = try XCTUnwrap(config["update"] as? [String: Any], "update")
        let feedURL = try XCTUnwrap(URL(string: try XCTUnwrap(update["feedURL"] as? String, "feedURL")))
        XCTAssertEqual(feedURL.scheme, "https")
        XCTAssertEqual(feedURL.pathExtension, "xml")
        XCTAssertFalse(try XCTUnwrap(update["bucket"] as? String, "bucket").isEmpty)
        XCTAssertNotNil(update["assetPrefix"] as? String, "assetPrefix")
        // Empty until the signing key is generated; a release refuses without it.
        XCTAssertNotNil(update["publicKey"] as? String, "publicKey")
    }

    func testTheVersionAndTheFeedAppearOnlyInTheConfiguration() throws {
        let config = try releaseConfiguration()
        let update = try XCTUnwrap(config["update"] as? [String: Any], "update")
        let host = try XCTUnwrap(URL(string: try XCTUnwrap(update["feedURL"] as? String))?.host, "feed host")
        let version = try XCTUnwrap(config["shortVersion"] as? String, "shortVersion")
        let team = try XCTUnwrap(config["teamIdentifier"] as? String, "teamIdentifier")

        var scanned = 0
        for directory in ["Sources", "Scripts", "Package.swift", "Tests"] {
            for (path, source) in textFiles(under: directory) {
                scanned += 1
                for (needle, what) in [(host, "the feed host"), (team, "the team identifier")] {
                    XCTAssertNil(source.range(of: needle), "\(path) repeats \(what)")
                }
                // The tests may name the version to assert on it; nothing else may.
                if path.hasPrefix("Tests/") == false {
                    XCTAssertNil(source.range(of: version), "\(path) repeats the version")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 10, "the scan found almost nothing to check")
    }

    func testTheLicencesShipAndNameTheFrameworkVersion() throws {
        for name in ["Sparkle.txt", "Hazmat.txt"] {
            let url = repositoryRoot().appendingPathComponent("Licenses/\(name)")
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertGreaterThan(text.count, 500, "\(name) looks truncated")
            XCTAssertTrue(text.contains("Permission is hereby granted, free of charge"), "\(name) is not a licence")
        }

        let manifest = try String(contentsOf: repositoryRoot().appendingPathComponent("Package.swift"), encoding: .utf8)
        let pinned = try XCTUnwrap(
            manifest.range(of: #"from: "(\d+\.\d+\.\d+)""#, options: .regularExpression).map { String(manifest[$0]) },
            "Package.swift pins no version for the update framework"
        )
        let version = pinned.replacingOccurrences(of: "from: \"", with: "").replacingOccurrences(of: "\"", with: "")
        XCTAssertTrue(
            try String(contentsOf: repositoryRoot().appendingPathComponent("Licenses/README.md"), encoding: .utf8)
                .contains(version),
            "Licenses/README.md does not name the pinned version \(version)"
        )
    }
}
