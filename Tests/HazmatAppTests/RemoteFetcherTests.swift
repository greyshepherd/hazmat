import Foundation
import HazmatAppSupport
import HazmatCore
import os
import XCTest
@testable import HazmatApp

/// A protocol that refuses every load and counts the ones it was asked for, so a
/// test can show that a refusal happened before the session was touched at all.
final class NeverLoads: URLProtocol {
    private static let attempts = OSAllocatedUnfairLock(initialState: 0)

    static var loads: Int { attempts.withLock { $0 } }

    static func reset() { attempts.withLock { $0 = 0 } }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.attempts.withLock { $0 += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

/// The fetcher's rules, and the one refusal it can take without an exchange. No
/// test here reaches the network: a plain-HTTP URL is refused before a request is
/// made, and a redirect is decided by the same value the delegate asks.
final class RemoteFetcherTests: XCTestCase {
    private let https = URL(string: "https://example.com/hosts.txt")!
    private let plain = URL(string: "http://example.com/hosts.txt")!

    // MARK: - The rules the delegate and a script both read

    func testAPlainHTTPURLIsRefusedAndAnHTTPRedirectIsNotFollowed() {
        let rules = RemoteExchangeRules.standard

        XCTAssertNil(rules.refusal(for: https), "an HTTPS URL is fetched")
        let refusal = rules.refusal(for: plain)
        XCTAssertNotNil(refusal)
        XCTAssertTrue(refusal?.contains("HTTPS") ?? false, refusal ?? "no reason")
        XCTAssertNil(rules.refusal(for: URL(string: "HTTPS://EXAMPLE.COM/x")!), "the scheme is read the way the URL reads it")

        XCTAssertTrue(rules.follows(https, after: 0), "a redirect that stays on HTTPS is followed")
        XCTAssertFalse(rules.follows(plain, after: 0), "a redirect to HTTP is not")
        XCTAssertFalse(rules.follows(nil, after: 0))
    }

    func testRedirectsAreBounded() {
        let rules = RemoteExchangeRules.standard

        XCTAssertTrue(rules.follows(https, after: rules.redirectLimit - 1))
        XCTAssertFalse(rules.follows(https, after: rules.redirectLimit), "the limit is the last one that is followed")
        XCTAssertFalse(rules.follows(https, after: rules.redirectLimit + 1))
    }

    func testTheBodyReadStopsAtTheStoresOwnBound() {
        let rules = RemoteExchangeRules.standard

        XCTAssertEqual(rules.bodyLimit, FetchBounds.bodySizeBound)
        XCTAssertNil(rules.bodyRefusal(received: rules.bodyLimit))
        let refusal = rules.bodyRefusal(received: rules.bodyLimit + 1)
        XCTAssertNotNil(refusal)
        XCTAssertTrue(refusal?.contains("\(rules.bodyLimit)") ?? false, refusal ?? "no reason")
    }

    func testTheRequestIsConditionalAndBoundedInTime() {
        let fetcher = URLSessionRemoteFetcher()
        let request = fetcher.urlRequest(
            for: RemoteFetchRequest(
                url: https,
                etag: "\"v1\"",
                lastModified: "Sat, 20 Sep 2026 12:00:00 GMT"
            )
        )

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, FetchBounds.exchangeTime)
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Modified-Since"), "Sat, 20 Sep 2026 12:00:00 GMT")

        let bare = fetcher.urlRequest(for: RemoteFetchRequest(url: https))
        XCTAssertNil(bare.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertNil(bare.value(forHTTPHeaderField: "If-Modified-Since"))
    }

    // MARK: - The refusal taken without an exchange

    func testFetchingAPlainHTTPURLIsRefusedWithoutARequest() async {
        let fetcher = URLSessionRemoteFetcher()

        let answer = await fetcher.fetch(RemoteFetchRequest(url: plain))

        XCTAssertEqual(answer.status, .refused)
        XCTAssertTrue(answer.reason?.contains("HTTPS") ?? false, answer.reason ?? "no reason")
        XCTAssertTrue(answer.body.isEmpty)
    }

    func testAURLWithNoSchemeIsRefused() async {
        let fetcher = URLSessionRemoteFetcher()

        let answer = await fetcher.fetch(RemoteFetchRequest(url: URL(string: "example.com/hosts.txt")!))

        XCTAssertEqual(answer.status, .refused)
        XCTAssertTrue(answer.reason?.contains("HTTPS") ?? false, answer.reason ?? "no reason")
    }

    func testARefusedURLIsNeverHandedToASession() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NeverLoads.self]
        let fetcher = URLSessionRemoteFetcher(configuration: configuration)
        NeverLoads.reset()

        let plainAnswer = await fetcher.fetch(RemoteFetchRequest(url: plain))
        let schemelessAnswer = await fetcher.fetch(RemoteFetchRequest(url: URL(string: "example.com/x")!))

        XCTAssertEqual(plainAnswer.status, .refused)
        XCTAssertEqual(schemelessAnswer.status, .refused)
        XCTAssertEqual(NeverLoads.loads, 0, "nothing was handed to a session: the refusal is taken first")
    }

    // MARK: - The network lives in this target and nowhere else

    func testOnlyTheApplicationTargetOpensASession() throws {
        for target in ["HazmatCore", "HazmatAppSupport", "HazmatPrivileged", "HazmatDaemon", "HazmatProtocol"] {
            for (file, source) in try sources(in: "Sources/\(target)") {
                XCTAssertNil(source.range(of: "URLSession"), "\(target)/\(file) opens a session")
            }
        }
    }

    func testThePrivilegedSideAndTheCoreHoldNoFetchAtAll() throws {
        let forbidden = ["RemoteFetching", "RemoteFetchRequest", "RemoteFetchAnswer", "http://"]

        for target in ["HazmatCore", "HazmatPrivileged", "HazmatDaemon", "HazmatProtocol"] {
            for (file, source) in try sources(in: "Sources/\(target)") {
                for needle in forbidden {
                    XCTAssertNil(source.range(of: needle), "\(target)/\(file) contains \(needle)")
                }
            }
        }

        let daemon = try String(contentsOf: repositoryRoot().appendingPathComponent("Sources/HazmatDaemon/main.swift"), encoding: .utf8)
        XCTAssertNil(daemon.range(of: "URL"), "the daemon holds no URL reference at all")
    }

    private func sources(in relativePath: String) throws -> [(String, String)] {
        let directory = repositoryRoot().appendingPathComponent(relativePath)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try files
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
