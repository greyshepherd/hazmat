import Foundation
import XCTest
@testable import HazmatCore

final class RemoteSourceTests: XCTestCase {
    // MARK: - 1.2 The sidecar's fields round trip

    func testEveryFieldOfASourceRoundTripsThroughItsSidecar() throws {
        let source = RemoteSource(
            url: URL(string: "https://example.com/hosts/blocklist.txt?token=abc&v=2")!,
            interval: 6 * 60 * 60,
            lastAttempt: Date(timeIntervalSince1970: 1_760_000_000),
            lastSuccess: Date(timeIntervalSince1970: 1_759_900_000),
            etag: "\"6d8f-1a2b\"",
            lastModified: "Sat, 20 Sep 2026 12:00:00 GMT",
            lastFailure: "the exchange timed out"
        )

        let restored = try RemoteSource.decode(source.encoded())

        XCTAssertEqual(restored, source)
        XCTAssertEqual(restored.url.query, "token=abc&v=2")
        XCTAssertEqual(restored.lastFailure, "the exchange timed out")
        XCTAssertEqual(restored.version, RemoteSource.currentVersion)
    }

    func testASourceWithNothingRecordedRoundTripsWithNothingRatherThanDefaults() throws {
        let source = RemoteSource(url: URL(string: "https://example.com/hosts.txt")!, interval: 86_400)

        let restored = try RemoteSource.decode(source.encoded())

        XCTAssertEqual(restored, source)
        XCTAssertNil(restored.lastAttempt)
        XCTAssertNil(restored.lastSuccess)
        XCTAssertNil(restored.etag)
        XCTAssertNil(restored.lastModified)
        XCTAssertNil(restored.lastFailure)
    }

    func testTheSidecarIsPlainTextThatNamesItsVersionAndItsFields() throws {
        let source = RemoteSource(url: URL(string: "https://example.com/hosts.txt")!, interval: 86_400)
        let text = String(decoding: try source.encoded(), as: UTF8.self)

        XCTAssertTrue(text.contains("\"version\""), text)
        XCTAssertTrue(text.contains("\"url\""), text)
        XCTAssertTrue(text.contains("\"interval\""), text)
        XCTAssertTrue(text.contains("https://example.com/hosts.txt"), text)
    }

    func testATruncatedSidecarIsATypedFailureRatherThanADefaultedSource() throws {
        let source = RemoteSource(url: URL(string: "https://example.com/hosts.txt")!, interval: 86_400)
        let whole = try source.encoded()
        let truncated = Data(whole.prefix(whole.count / 2))

        XCTAssertThrowsError(try RemoteSource.decode(truncated)) { error in
            guard case .unreadable(let reason)? = error as? RemoteSourceError else {
                return XCTFail("expected an unreadable refusal, got \(error)")
            }
            XCTAssertFalse(reason.isEmpty)
        }

        XCTAssertThrowsError(try RemoteSource.decode(Data())) { error in
            guard case .unreadable? = error as? RemoteSourceError else {
                return XCTFail("expected an unreadable refusal, got \(error)")
            }
        }
    }

    func testASidecarFromAnUnknownVersionIsRefusedRatherThanRead() throws {
        let text = """
        {
          "interval" : 86400,
          "url" : "https://example.com/hosts.txt",
          "version" : 99
        }
        """

        XCTAssertThrowsError(try RemoteSource.decode(bytes(text))) { error in
            XCTAssertEqual(error as? RemoteSourceError, .unsupportedVersion(found: 99))
            XCTAssertTrue((error as? RemoteSourceError)?.description.contains("99") ?? false)
        }
    }

    func testASidecarThatIsNotJSONAndOneMissingTheVersionAreBothUnreadable() throws {
        XCTAssertThrowsError(try RemoteSource.decode(bytes("not a sidecar at all"))) { error in
            guard case .unreadable? = error as? RemoteSourceError else {
                return XCTFail("expected an unreadable refusal, got \(error)")
            }
        }

        let missingVersion = """
        { "url" : "https://example.com/hosts.txt", "interval" : 86400 }
        """
        XCTAssertThrowsError(try RemoteSource.decode(bytes(missingVersion))) { error in
            guard case .unreadable? = error as? RemoteSourceError else {
                return XCTFail("expected an unreadable refusal, got \(error)")
            }
        }

        let missingURL = """
        { "version" : 1, "interval" : 86400 }
        """
        XCTAssertThrowsError(try RemoteSource.decode(bytes(missingURL))) { error in
            guard case .unreadable? = error as? RemoteSourceError else {
                return XCTFail("expected an unreadable refusal, got \(error)")
            }
        }
    }

    // MARK: - 1.4 The fetch bounds are named once each

    func testTheBodyBoundIsTheAppliedBlocksBoundAndTheRefusalNamesIt() {
        XCTAssertEqual(FetchBounds.bodySizeBound, PlannedBytes.sizeBound)

        let refusal = FetchBounds.oversizedBody(PlannedBytes.sizeBound + 1)
        XCTAssertTrue(refusal.contains("\(PlannedBytes.sizeBound)"), refusal)

        XCTAssertGreaterThan(FetchBounds.exchangeTime, 0)
        XCTAssertTrue(FetchBounds.exchangeTimedOut.contains("\(Int(FetchBounds.exchangeTime))"))
    }
}
