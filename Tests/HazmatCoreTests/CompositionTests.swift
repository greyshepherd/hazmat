import XCTest
@testable import HazmatCore

final class CompositionTests: XCTestCase {
    func testLaterLayerWinsAConflictingAddress() throws {
        let result = try composition(
            fragments: [
                ("base", "10.0.0.5\tapi.example.com\n"),
                ("blocklist", "127.0.0.1\tapi.example.com\n")
            ],
            profile: "base\nblocklist\n"
        )

        XCTAssertEqual(result.address(of: "api.example.com", .ipv4), "127.0.0.1")
        XCTAssertEqual(result.resolved.count, 1)
    }

    func testReorderingTheStackChangesTheWinner() throws {
        let result = try composition(
            fragments: [
                ("base", "10.0.0.5\tapi.example.com\n"),
                ("blocklist", "127.0.0.1\tapi.example.com\n")
            ],
            profile: "blocklist\nbase\n"
        )

        XCTAssertEqual(result.address(of: "api.example.com", .ipv4), "10.0.0.5")
        XCTAssertEqual(result.resolved.count, 1)
    }

    func testAddressFamiliesUnionInsteadOfConflicting() throws {
        let result = try composition(
            fragments: [
                ("base", "127.0.0.1\tapi.example.com\n"),
                ("project", "::1\tapi.example.com\n")
            ],
            profile: "base\nproject\n"
        )

        XCTAssertEqual(result.address(of: "api.example.com", .ipv4), "127.0.0.1")
        XCTAssertEqual(result.address(of: "api.example.com", .ipv6), "::1")
        XCTAssertEqual(result.displacements, [])
    }

    func testARemovalStrikesANameALowerLayerSupplied() throws {
        let result = try composition(
            fragments: [
                ("base", "0.0.0.0\tads.example.com\n"),
                ("blocklist", "# hazmat:remove ads.example.com\n")
            ],
            profile: "base\nblocklist\n"
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testARemovalStrikesEveryFamilyOfAName() throws {
        let result = try composition(
            fragments: [
                ("base", "0.0.0.0\tads.example.com\n::1\tads.example.com\n"),
                ("blocklist", "# hazmat:remove ads.example.com\n")
            ],
            profile: "base\nblocklist\n"
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testRemovingANameNoLowerLayerSuppliesIsHarmless() throws {
        let withoutRemoval = try composition(
            fragments: [("base", "0.0.0.0\tads.example.com\n")],
            profile: "base\n"
        )
        let withRemoval = try composition(
            fragments: [
                ("base", "0.0.0.0\tads.example.com\n"),
                ("blocklist", "# hazmat:remove nothing.example.com\n")
            ],
            profile: "base\nblocklist\n"
        )

        XCTAssertEqual(withRemoval.resolved, withoutRemoval.resolved)
        XCTAssertEqual(withRemoval.displacements, [])
    }

    func testALaterLayerMaySupplyANameAnEarlierLayerRemoved() throws {
        let result = try composition(
            fragments: [
                ("base", "0.0.0.0\tads.example.com\n"),
                ("blocklist", "# hazmat:remove ads.example.com\n"),
                ("project", "127.0.0.1\tads.example.com\n")
            ],
            profile: "base\nblocklist\nproject\n"
        )

        XCTAssertEqual(result.address(of: "ads.example.com", .ipv4), "127.0.0.1")
    }

    func testResolutionIsKeyedOnAliasesToo() throws {
        let result = try composition(
            fragments: [
                ("base", "10.0.0.1\tapi.example.com api\n"),
                ("project", "127.0.0.1\tapi\n")
            ],
            profile: "base\nproject\n"
        )

        XCTAssertEqual(result.address(of: "api.example.com", .ipv4), "10.0.0.1")
        XCTAssertEqual(result.address(of: "api", .ipv4), "127.0.0.1")
        XCTAssertEqual(result.resolved.count, 2)
        XCTAssertEqual(result.displacements.map(\.name), ["api"])
    }

    func testOrderIsWinningLayerThenLineThenNameWithinTheLine() throws {
        let result = try composition(
            fragments: [
                ("base", "10.0.0.9\tzzz.example.com\n# a comment\n10.0.0.8\taaa.example.com\n"),
                ("project", "10.0.0.7\tmmm.example.com\n"),
                ("blocklist", "10.0.0.6\tbeta.example.com alpha.example.com\n")
            ],
            profile: "base\nproject\nblocklist\n"
        )

        XCTAssertEqual(
            result.orderedNames,
            [
                "zzz.example.com",     // base, line 1
                "aaa.example.com",     // base, line 3
                "mmm.example.com",     // project, line 1
                "beta.example.com",    // blocklist, line 1, as written
                "alpha.example.com"
            ]
        )
    }

    func testRepeatedCompositionIsIdentical() throws {
        let fragments = [
            ("base", "10.0.0.5\tapi.example.com\n127.0.0.1\tlocalhost\n"),
            ("project", "127.0.0.1\tapi.example.com api\n"),
            ("blocklist", "0.0.0.0\tads.example.com\n# hazmat:remove localhost\n")
        ]

        let first = try composition(fragments: fragments, profile: "base\nproject\nblocklist\n")
        let second = try composition(fragments: fragments, profile: "base\nproject\nblocklist\n")

        XCTAssertEqual(first, second)
    }

    func testFragmentsTheProfileNeverNamesDoNotLeakIn() throws {
        let named = try composition(
            fragments: [("base", "10.0.0.1\tfirst.example\n")],
            profile: "base\n"
        )
        let withExtraFragments = try composition(
            fragments: [
                ("base", "10.0.0.1\tfirst.example\n"),
                ("unused", "10.0.0.9\tfirst.example\n10.0.0.9\tstray.example\n"),
                ("also-unused", "# hazmat:remove first.example\n")
            ],
            profile: "base\n"
        )

        XCTAssertEqual(withExtraFragments, named)
    }

    func testEachNameIsResolvedOncePerFamily() throws {
        let result = try composition(
            fragments: [
                ("base", "127.0.0.1\tapi.example.com\n"),
                ("project", "127.0.0.2\tapi.example.com\n127.0.0.3\tapi.example.com\n")
            ],
            profile: "base\nproject\n"
        )

        XCTAssertEqual(result.familyCount(of: "api.example.com"), 1)
        XCTAssertEqual(result.address(of: "api.example.com", .ipv4), "127.0.0.3")
        XCTAssertEqual(result.displacements.count, 2)
    }
}
