import XCTest
@testable import HazmatCore

final class ResolutionReportTests: XCTestCase {
    private let work = ProfileID("work")

    func testTheSupplyFragmentOfEveryResolvedEntryIsRecorded() throws {
        let result = try composition(
            fragments: [
                ("base", "# base\n127.0.0.1\tlocalhost\n::1\tlocalhost\n"),
                ("project", "10.0.0.4\tproject.example.com\n")
            ],
            profile: "base\nproject\n"
        )

        XCTAssertEqual(result.resolved.count, 3)
        XCTAssertEqual(
            result.resolved.first { $0.name == "localhost" && $0.family == .ipv4 }?.source,
            SourceLocation(fragment: FragmentID("base"), line: 2)
        )
        XCTAssertEqual(
            result.resolved.first { $0.name == "localhost" && $0.family == .ipv6 }?.source,
            SourceLocation(fragment: FragmentID("base"), line: 3)
        )
        XCTAssertEqual(
            result.resolved.first { $0.name == "project.example.com" }?.source,
            SourceLocation(fragment: FragmentID("project"), line: 1)
        )
    }

    func testDisplacedEntriesAreReportedInFull() throws {
        let result = try composition(
            fragments: [
                ("base", "10.0.0.5\tapi.example.com\n"),
                ("project", "127.0.0.1\tapi.example.com\n")
            ],
            profile: "base\nproject\n"
        )

        XCTAssertEqual(result.displacements, [
            Displacement(
                name: "api.example.com",
                family: .ipv4,
                address: "10.0.0.5",
                source: SourceLocation(fragment: FragmentID("base"), line: 1),
                displacedBy: SourceLocation(fragment: FragmentID("project"), line: 1)
            )
        ])
    }

    func testAnAliasConflictIsReportedWithBothFragments() throws {
        let result = try composition(
            fragments: [
                ("base", "10.0.0.1\tapi.example.com api\n"),
                ("project", "127.0.0.1\tapi\n")
            ],
            profile: "base\nproject\n"
        )

        XCTAssertEqual(result.displacements, [
            Displacement(
                name: "api",
                family: .ipv4,
                address: "10.0.0.1",
                source: SourceLocation(fragment: FragmentID("base"), line: 1),
                displacedBy: SourceLocation(fragment: FragmentID("project"), line: 1)
            )
        ])
    }

    func testEveryDisplacementOfOneEntryIsReported() throws {
        let result = try composition(
            fragments: [
                ("base", "10.0.0.1\tapi.example.com api\n"),
                ("project", "127.0.0.1\tapi.example.com api\n")
            ],
            profile: "base\nproject\n"
        )

        XCTAssertEqual(result.displacements.map(\.name), ["api.example.com", "api"])
        XCTAssertEqual(result.displacements.map(\.address), ["10.0.0.1", "10.0.0.1"])
        XCTAssertEqual(
            result.displacements.map(\.displacedBy),
            [
                SourceLocation(fragment: FragmentID("project"), line: 1),
                SourceLocation(fragment: FragmentID("project"), line: 1)
            ]
        )
    }

    func testConflictsWithinOneFragmentAreReported() throws {
        let result = try composition(
            fragments: [("base", "10.0.0.1\tapi.example.com\n10.0.0.2\tapi.example.com\n")],
            profile: "base\n"
        )

        XCTAssertEqual(result.displacements, [
            Displacement(
                name: "api.example.com",
                family: .ipv4,
                address: "10.0.0.1",
                source: SourceLocation(fragment: FragmentID("base"), line: 1),
                displacedBy: SourceLocation(fragment: FragmentID("base"), line: 2)
            )
        ])
    }

    func testTheReportNeedsOneCompositionPass() throws {
        let store = CountingStore(
            fragments: [
                FragmentID("base"): "10.0.0.5\tapi.example.com\n127.0.0.1\tlocalhost\n",
                FragmentID("project"): "127.0.0.1\tapi.example.com\n",
                FragmentID("blocklist"): "0.0.0.0\tads.example.com\n"
            ],
            profiles: [work: "base\nproject\nblocklist\n"]
        )

        let result = try HostsComposer(store: store).compose(profile: work)

        XCTAssertEqual(store.profileReads, [work])
        XCTAssertEqual(store.fragmentReads, [FragmentID("base"), FragmentID("project"), FragmentID("blocklist")])

        // Everything a caller can ask for is already in hand.
        XCTAssertEqual(result.orderedNames, ["localhost", "api.example.com", "ads.example.com"])
        XCTAssertEqual(result.displacements.count, 1)
        XCTAssertEqual(
            result.resolved.first { $0.name == "api.example.com" }?.source,
            SourceLocation(fragment: FragmentID("project"), line: 1)
        )
        XCTAssertEqual(store.profileReads, [work])
        XCTAssertEqual(store.fragmentReads.count, 3)
    }
}
