import XCTest
@testable import HazmatCore

final class ProfileLoadingTests: XCTestCase {
    private let work = ProfileID("work")

    func testReferencesComposeInFileOrder() throws {
        let store = InMemoryStore(
            fragments: [
                FragmentID("base"): "10.0.0.1 first.example\n",
                FragmentID("project"): "10.0.0.2 second.example\n",
                FragmentID("blocklist"): "10.0.0.3 third.example\n"
            ],
            profiles: [work: "base\nproject\nblocklist\n"]
        )

        let result = try HostsComposer(store: store).compose(profile: work)

        XCTAssertEqual(result.orderedNames, ["first.example", "second.example", "third.example"])
        XCTAssertEqual(
            result.orderedSources.map(\.fragment),
            [FragmentID("base"), FragmentID("project"), FragmentID("blocklist")]
        )
    }

    func testReorderingTheReferencesChangesTheStack() throws {
        let store = InMemoryStore(
            fragments: [
                FragmentID("base"): "10.0.0.1 first.example\n",
                FragmentID("project"): "10.0.0.2 second.example\n"
            ],
            profiles: [work: "project\nbase\n"]
        )

        let result = try HostsComposer(store: store).compose(profile: work)

        XCTAssertEqual(result.orderedNames, ["second.example", "first.example"])
    }

    func testCommentsAndBlankLinesArePermitted() throws {
        let store = InMemoryStore(
            fragments: [FragmentID("base"): "10.0.0.1 first.example\n"],
            profiles: [work: "# a stack\n\nbase\n   # trailing comment\n"]
        )

        let result = try HostsComposer(store: store).compose(profile: work)

        XCTAssertEqual(result.orderedNames, ["first.example"])
    }

    func testMissingFragmentErrorNamesTheFragment() {
        let store = InMemoryStore(profiles: [work: "# stack\nbase\nproject\n"])

        let problems = compositionProblems(store, work)

        XCTAssertEqual(problems, [
            .missingFragment(profile: work, line: 2, fragment: FragmentID("base")),
            .missingFragment(profile: work, line: 3, fragment: FragmentID("project"))
        ])
        XCTAssertTrue(problems[0].message.contains("base"))
        XCTAssertTrue(problems[0].message.contains("not in the store"))
    }

    func testMissingProfileIsReported() {
        let problems = compositionProblems(InMemoryStore(), work)

        XCTAssertEqual(problems, [.missingProfile(work)])
    }

    func testMalformedReferenceIsReported() {
        let store = InMemoryStore(
            fragments: [FragmentID("base"): "10.0.0.1 first.example\n"],
            profiles: [work: "base\n../escape\n"]
        )

        let problems = compositionProblems(store, work)

        XCTAssertEqual(problems, [.malformedReference(profile: work, line: 2, text: "../escape")])
    }

    func testExternalEditIsPickedUpByTheNextComposition() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let composer = HostsComposer(store: workspace.store)

        let before = try composer.compose(profile: work)
        XCTAssertEqual(before.address(of: "api.internal", .ipv4), "127.0.0.1")

        try workspace.write("10.9.9.9\tapi.internal\n", to: "fragments/project.hosts")

        let after = try composer.compose(profile: work)
        XCTAssertEqual(after.address(of: "api.internal", .ipv4), "10.9.9.9")
        XCTAssertEqual(after.address(of: "api", .ipv4), nil)
    }

    func testAFragmentSolvedByAFileIsSolvedByNameNotByEnumeration() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }

        let result = try HostsComposer(store: workspace.store).compose(profile: work)

        XCTAssertEqual(result.orderedNames.first, "localhost")
        XCTAssertEqual(result.address(of: "api.internal", .ipv4), "127.0.0.1")
    }
}
