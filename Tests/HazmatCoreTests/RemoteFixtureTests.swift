import Foundation
import XCTest
@testable import HazmatCore

/// The fixture store carries a source beside its fragments: one recorded origin
/// with a fragment, and one sidecar whose fragment is not there. The rest of the
/// fixture is unchanged, so every composition and store test answers as before.
final class RemoteFixtureTests: XCTestCase {
    private let layout = StoreLayout(root: Bundle.module.resourceURL!.appendingPathComponent("Fixtures/store"))

    func testTheFixtureStoreListsItsSourcesAndKeepsItsFragments() throws {
        XCTAssertEqual(try Fixture.url(directory: "store").lastPathComponent, "store")
        XCTAssertEqual(layout.fragments().map(\.rawValue), ["base", "blocklist", "project"])
        XCTAssertEqual(layout.remoteSources().map(\.rawValue), ["blocklist", "orphan"])
        XCTAssertEqual(layout.profiles().map(\.rawValue), ["work"])
    }

    func testTheRecordedOriginDecodesWithItsURLIntervalAndState() throws {
        let data = try Data(contentsOf: layout.remoteURL(FragmentID("blocklist")))
        let source = try RemoteSource.decode(data)

        XCTAssertEqual(source.version, RemoteSource.currentVersion)
        XCTAssertEqual(source.url.absoluteString, "https://someonewhocares.org/hosts/zero/hosts")
        XCTAssertEqual(source.interval, 86_400)
        XCTAssertEqual(source.etag, "\"6d8f-1a2b\"")
        XCTAssertEqual(source.lastModified, "Fri, 19 Sep 2026 04:00:00 GMT")
        XCTAssertEqual(source.lastSuccess, ISO8601DateFormatter().date(from: "2026-09-19T04:00:00Z"))
        XCTAssertNil(source.lastFailure)
    }

    func testTheOriginTravelsWithACopiedStore() throws {
        let copy = try Workspace()
        defer { copy.remove() }
        let copied = StoreLayout(root: copy.root)

        // The same two sources, read from the copy rather than the bundle, with
        // every field the origin records.
        XCTAssertEqual(copied.remoteSources(), layout.remoteSources())
        let source = try RemoteSource.decode(Data(contentsOf: copied.remoteURL(FragmentID("blocklist"))))
        XCTAssertEqual(source.url.absoluteString, "https://someonewhocares.org/hosts/zero/hosts")
        XCTAssertEqual(source.interval, 86_400)
        XCTAssertEqual(source.etag, "\"6d8f-1a2b\"")
        XCTAssertEqual(source.lastSuccess, ISO8601DateFormatter().date(from: "2026-09-19T04:00:00Z"))
        XCTAssertEqual(copied.fragments(), layout.fragments(), "the fragments travelled with it")
    }

    func testASidecarWhoseFragmentIsNotThereIsStillASource() throws {
        let data = try Data(contentsOf: layout.remoteURL(FragmentID("orphan")))
        let source = try RemoteSource.decode(data)

        XCTAssertFalse(layout.fragments().contains(FragmentID("orphan")), "the fixture holds no fragment for it")
        XCTAssertEqual(source.url.host(), "example.invalid")
        XCTAssertEqual(source.interval, RemoteIntervalFixture.manual)
        XCTAssertEqual(source.lastFailure, "the source record's fragment is not in the store")
        XCTAssertNil(source.lastSuccess)
    }

    func testTheFixturesCompositionIsUnchangedByTheSourceBesideIt() throws {
        // The origin is invisible to composition: `remote/` is not a fragment
        // namespace, so a store with sources composes exactly as the same store
        // without them does.
        let withSources = try workComposition()

        let without = try Workspace()
        defer { without.remove() }
        try FileManager.default.removeItem(at: without.root.appendingPathComponent("remote"))
        let withoutSources = try HostsComposer(store: without.store).compose(profile: ProfileID("work"))

        XCTAssertEqual(withSources, withoutSources)
        XCTAssertEqual(
            withSources.resolved.first { $0.name == "ads.example.com" }?.source.fragment,
            FragmentID("blocklist"),
            "the fetched fragment is an ordinary fragment to composition"
        )
    }
}

/// Zero, written where the fixture file is read rather than through the app
/// support policy, which the core does not hold.
private enum RemoteIntervalFixture {
    static let manual: TimeInterval = 0
}

private extension URL {
    func host() -> String? { host }
}
