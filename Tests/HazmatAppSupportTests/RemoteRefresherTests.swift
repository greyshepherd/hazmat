import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

/// A fetcher that answers from a script. Nothing here reaches the network: the
/// seam is the whole of the network's reach in the suite.
actor StubFetcher: RemoteFetching {
    private var remaining: [RemoteFetchAnswer]
    private var recorded: [RemoteFetchRequest] = []

    init(_ answers: [RemoteFetchAnswer]) {
        remaining = answers
    }

    init(_ answer: RemoteFetchAnswer) {
        remaining = [answer]
    }

    func fetch(_ request: RemoteFetchRequest) async -> RemoteFetchAnswer {
        recorded.append(request)
        guard remaining.count > 1 else {
            return remaining.first ?? .refused("nothing was scripted")
        }
        return remaining.removeFirst()
    }

    var requests: [RemoteFetchRequest] { recorded }

    var count: Int { recorded.count }
}

/// A throwaway store root, with the sidecar read back as a value.
private final class RemoteStore {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hazmat-remote-\(UUID().uuidString)")
    }

    var layout: StoreLayout { StoreLayout(root: root) }

    func write(_ contents: String, to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Every file under the root, relative to it, so a stray temporary file is
    /// visible.
    func entries() -> [String] {
        let subpaths = (try? FileManager.default.subpathsOfDirectory(atPath: root.path)) ?? []
        return subpaths.filter { path in
            var isDirectory: ObjCBool = false
            let full = root.appendingPathComponent(path).path
            let exists = FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory)
            return exists && !isDirectory.boolValue
        }
        .sorted()
    }

    func fragmentState(_ name: String) throws -> FileState? {
        let url = layout.fragmentURL(FragmentID(name))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try FileState(of: url)
    }

    func fragmentText(_ name: String) throws -> String? {
        let url = layout.fragmentURL(FragmentID(name))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func source(_ name: String) throws -> RemoteSource {
        try RemoteSource.decode(Data(contentsOf: layout.remoteURL(FragmentID(name))))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

final class RemoteRefresherTests: XCTestCase {
    private let blocklist = FragmentID("blocklist")
    private let https = URL(string: "https://example.com/hosts.txt")!

    private func refresher(_ store: RemoteStore, _ fetcher: StubFetcher) -> RemoteRefresher {
        RemoteRefresher(layout: store.layout, fetcher: fetcher)
    }

    private func source(
        _ url: URL? = nil,
        interval: TimeInterval = 86_400,
        etag: String? = nil,
        lastModified: String? = nil
    ) -> RemoteSource {
        RemoteSource(
            url: url ?? https,
            interval: interval,
            lastAttempt: Date(timeIntervalSince1970: 1_759_000_000),
            lastSuccess: Date(timeIntervalSince1970: 1_759_000_000),
            etag: etag,
            lastModified: lastModified
        )
    }

    private let body = "0.0.0.0\tads.example.com\n"

    // MARK: - 2.1 The seam

    func testAScriptedFetcherAnswersTheSeamAndCarriesTheValidators() async throws {
        let store = RemoteStore()
        defer { store.remove() }
        let fetcher = StubFetcher(.succeeded(body: bytes(body), etag: "v2", finalURL: https))
        let refresher = refresher(store, fetcher)

        let result = await refresher.refresh(
            fragment: blocklist,
            source: source(etag: "\"v1\"", lastModified: "Sat, 20 Sep 2026 12:00:00 GMT"),
            at: Date(timeIntervalSince1970: 1_760_000_000)
        )

        XCTAssertEqual(result.outcome, .wrote)
        let requests = await fetcher.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url, https)
        XCTAssertEqual(requests.first?.etag, "\"v1\"")
        XCTAssertEqual(requests.first?.lastModified, "Sat, 20 Sep 2026 12:00:00 GMT")
        XCTAssertEqual(try store.fragmentText("blocklist"), body)
    }

    // MARK: - 2.2 What a fetch refuses

    func testANonHTTPSURLIsRefusedAndNoExchangeIsMade() async throws {
        let store = RemoteStore()
        defer { store.remove() }
        let fetcher = StubFetcher(.succeeded(body: bytes(body), finalURL: https))
        let refresher = refresher(store, fetcher)
        let plain = URL(string: "http://example.com/hosts.txt")!

        let result = await refresher.refresh(fragment: blocklist, source: source(plain), at: Date())

        XCTAssertTrue(result.wasRefused)
        XCTAssertEqual(
            result.reason,
            "'http://example.com/hosts.txt' is not an HTTPS URL. A source is fetched over HTTPS only."
        )
        let exchanges = await fetcher.count
        XCTAssertEqual(exchanges, 0, "an HTTP URL is refused before the network sees it")
        XCTAssertNil(try store.fragmentState("blocklist"), "nothing is created")
    }

    func testARedirectThatLeavesHTTPSIsRefused() async throws {
        let store = RemoteStore()
        defer { store.remove() }
        let plain = URL(string: "http://mirror.example.com/hosts.txt")!
        let fetcher = StubFetcher(.succeeded(body: bytes(body), finalURL: plain))
        let refresher = refresher(store, fetcher)

        let result = await refresher.refresh(fragment: blocklist, source: source(), at: Date())

        XCTAssertTrue(result.wasRefused)
        XCTAssertEqual(
            result.reason,
            "the exchange was redirected to 'http://mirror.example.com/hosts.txt', which is not an HTTPS URL."
        )
        XCTAssertNil(try store.fragmentState("blocklist"))
    }

    func testAFailureStatusIsRefusedWithTheExchangesOwnReason() async throws {
        let store = RemoteStore()
        defer { store.remove() }
        let fetcher = StubFetcher(.refused("the server answered 503", finalURL: https))
        let refresher = refresher(store, fetcher)

        let result = await refresher.refresh(fragment: blocklist, source: source(), at: Date())

        XCTAssertEqual(result.reason, "the server answered 503")
        XCTAssertNil(try store.fragmentState("blocklist"))
    }

    func testABodyOverTheBoundIsRefusedWithAReasonNamingIt() async throws {
        let store = RemoteStore()
        defer { store.remove() }
        let oversized = Data(repeating: UInt8(ascii: "a"), count: FetchBounds.bodySizeBound + 1)
        let fetcher = StubFetcher(.succeeded(body: oversized, finalURL: https))
        let refresher = refresher(store, fetcher)

        let result = await refresher.refresh(fragment: blocklist, source: source(), at: Date())

        XCTAssertTrue(result.wasRefused)
        XCTAssertTrue(result.reason?.contains("\(FetchBounds.bodySizeBound)") ?? false, result.reason ?? "no reason")
        XCTAssertNil(try store.fragmentState("blocklist"))
    }

    func testABodyThatIsNotUTF8IsRefused() async throws {
        let store = RemoteStore()
        defer { store.remove() }
        let invalid = Data([0x30, 0x2E, 0x30, 0x2E, 0x30, 0x2E, 0x30, 0x09, 0xFF, 0xFE, 0x0A])
        let fetcher = StubFetcher(.succeeded(body: invalid, finalURL: https))
        let refresher = refresher(store, fetcher)

        let result = await refresher.refresh(fragment: blocklist, source: source(), at: Date())

        XCTAssertTrue(result.wasRefused)
        XCTAssertTrue(result.reason?.contains("UTF-8") ?? false, result.reason ?? "no reason")
        XCTAssertNil(try store.fragmentState("blocklist"))
    }

    func testABodyCarryingADirectiveIsRefusedWhole() async throws {
        for directive in [
            "# hazmat:remove ads.example.com\n0.0.0.0\tads.example.com\n",
            "#hazmat:remove ads.example.com\n",
            "#  hazmat:remove ads.example.com\n",
            "# hazmat:somethingelse\n"
        ] {
            let store = RemoteStore()
            defer { store.remove() }
            let fetcher = StubFetcher(.succeeded(body: bytes(directive), finalURL: https))
            let refresher = refresher(store, fetcher)

            let result = await refresher.refresh(fragment: blocklist, source: source(), at: Date())

            XCTAssertTrue(result.wasRefused, directive)
            XCTAssertTrue(result.reason?.contains("hazmat:") ?? false, result.reason ?? "no reason")
            XCTAssertNil(try store.fragmentState("blocklist"), directive)
        }
    }

    func testARefusedAnswerLeavesAnExistingFragmentExactlyAsItWas() async throws {
        let store = RemoteStore()
        defer { store.remove() }
        try store.write(body, to: "fragments/blocklist.hosts")
        let before = try XCTUnwrap(try store.fragmentState("blocklist"))
        let fetcher = StubFetcher(.succeeded(body: bytes("# hazmat:remove x\n"), finalURL: https))
        let refresher = refresher(store, fetcher)

        let result = await refresher.refresh(fragment: blocklist, source: source(), at: Date())

        XCTAssertTrue(result.wasRefused)
        XCTAssertEqual(try store.fragmentState("blocklist"), before)
    }

    // MARK: - 2.3 What a refresh writes

    func testFetchedTextThatDiffersIsWrittenThroughTheStoreWriterAndLeavesNoTemporaryFile() async throws {
        let store = RemoteStore()
        defer { store.remove() }
        try store.write("127.0.0.1\tstale.example.com\n", to: "fragments/blocklist.hosts")
        let fetcher = StubFetcher(.succeeded(body: bytes(body), etag: "\"v2\"", finalURL: https))
        let refresher = refresher(store, fetcher)

        let result = await refresher.refresh(
            fragment: blocklist,
            source: source(etag: "\"v1\""),
            at: Date(timeIntervalSince1970: 1_760_000_000)
        )

        XCTAssertEqual(result.outcome, .wrote)
        XCTAssertEqual(try store.fragmentText("blocklist"), body)
        XCTAssertEqual(store.entries(), ["fragments/blocklist.hosts", "remote/blocklist.remote"])
        XCTAssertEqual(result.source.lastSuccess, Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertEqual(result.source.etag, "\"v2\"")
        XCTAssertNil(result.source.lastFailure)
        XCTAssertEqual(try store.source("blocklist"), result.source)
    }

    func testAnIdenticalBodyIsNotRewritten() async throws {
        let store = RemoteStore()
        defer { store.remove() }
        try store.write(body, to: "fragments/blocklist.hosts")
        let before = try XCTUnwrap(try store.fragmentState("blocklist"))
        let fetcher = StubFetcher(.succeeded(body: bytes(body), finalURL: https))
        let refresher = refresher(store, fetcher)
        let now = Date(timeIntervalSince1970: 1_760_000_000)

        let result = await refresher.refresh(fragment: blocklist, source: source(), at: now)

        XCTAssertEqual(result.outcome, .unchanged)
        XCTAssertEqual(try store.fragmentState("blocklist"), before, "the bytes and the modification time are both untouched")
        XCTAssertEqual(result.source.lastSuccess, now, "the refresh still counts as a success")
        XCTAssertEqual(store.entries(), ["fragments/blocklist.hosts", "remote/blocklist.remote"])
    }

    func testANotModifiedAnswerWritesNothingAndRecordsASuccess() async throws {
        let store = RemoteStore()
        defer { store.remove() }
        try store.write(body, to: "fragments/blocklist.hosts")
        let before = try XCTUnwrap(try store.fragmentState("blocklist"))
        let fetcher = StubFetcher(.notModified(etag: "\"v1\"", finalURL: https))
        let refresher = refresher(store, fetcher)
        let now = Date(timeIntervalSince1970: 1_760_000_000)

        let result = await refresher.refresh(fragment: blocklist, source: source(etag: "\"v1\""), at: now)

        XCTAssertEqual(result.outcome, .unchanged)
        XCTAssertEqual(try store.fragmentState("blocklist"), before)
        XCTAssertEqual(result.source.lastSuccess, now)
        XCTAssertNil(result.source.lastFailure)
        XCTAssertEqual(result.source.etag, "\"v1\"")
    }

    func testAFailedExchangeKeepsThePreviousTextAndRecordsTheReason() async throws {
        let store = RemoteStore()
        defer { store.remove() }
        try store.write(body, to: "fragments/blocklist.hosts")
        let before = try XCTUnwrap(try store.fragmentState("blocklist"))
        let fetcher = StubFetcher(.refused("the exchange timed out", finalURL: https))
        let refresher = refresher(store, fetcher)
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let had = source(etag: "\"v1\"")

        let result = await refresher.refresh(fragment: blocklist, source: had, at: now)

        XCTAssertTrue(result.wasRefused)
        XCTAssertEqual(try store.fragmentState("blocklist"), before, "the previous text stays readable")
        XCTAssertEqual(result.source.lastFailure, "the exchange timed out")
        XCTAssertEqual(result.source.lastAttempt, now)
        XCTAssertEqual(result.source.lastSuccess, had.lastSuccess, "a failed attempt is not a success")
        XCTAssertEqual(result.source.etag, "\"v1\"", "the validators still describe the text the fragment holds")
        XCTAssertEqual(try store.source("blocklist").lastFailure, "the exchange timed out")
    }

    func testAWriteThatFailsKeepsThePreviousTextAndRecordsTheReason() async throws {
        let store = RemoteStore()
        defer { store.remove() }
        try store.write(body, to: "fragments/blocklist.hosts")
        let before = try XCTUnwrap(try store.fragmentState("blocklist"))
        // The fragments directory refuses a new file, so the write cannot land
        // while the text it would replace stays readable.
        let fragments = store.layout.fragmentsDirectory
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fragments.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fragments.path) }
        let fetcher = StubFetcher(.succeeded(body: bytes("0.0.0.0\tnew.example.com\n"), finalURL: https))
        let refresher = refresher(store, fetcher)
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let had = source()

        let result = await refresher.refresh(fragment: blocklist, source: had, at: now)

        XCTAssertTrue(result.wasRefused)
        XCTAssertFalse(result.reason?.isEmpty ?? true, "the write's own reason is reported")
        XCTAssertEqual(try store.fragmentState("blocklist"), before, "the previous text stays readable")
        XCTAssertEqual(result.source.lastFailure, result.reason)
        XCTAssertEqual(result.source.lastSuccess, had.lastSuccess, "a failed write is not a success")
        XCTAssertEqual(try store.source("blocklist").lastFailure, result.reason)
        XCTAssertEqual(
            store.entries(),
            ["fragments/blocklist.hosts", "remote/blocklist.remote"],
            "no temporary file is left behind"
        )
    }

    func testARefreshOfASourceWhoseFragmentIsNotThereYetWritesTheFirstBody() async throws {
        let store = RemoteStore()
        defer { store.remove() }
        // A first fetch that failed: a sidecar and no fragment.
        try store.write("{\"version\":1,\"url\":\"https://example.com/hosts.txt\",\"interval\":86400}\n", to: "remote/blocklist.remote")
        XCTAssertNil(try store.fragmentState("blocklist"))
        let fetcher = StubFetcher(.succeeded(body: bytes(body), finalURL: https))
        let refresher = refresher(store, fetcher)

        let result = await refresher.refresh(fragment: blocklist, source: try store.source("blocklist"), at: Date())

        XCTAssertEqual(result.outcome, .wrote)
        XCTAssertEqual(try store.fragmentText("blocklist"), body)
        XCTAssertEqual(store.layout.remoteSources(), [blocklist])
    }
}
