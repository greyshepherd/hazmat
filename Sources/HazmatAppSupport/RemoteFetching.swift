import Foundation

/// One exchange's request: the URL, and the validators the last answer carried.
/// The conditional headers are the fetcher's business; this says what they are.
public struct RemoteFetchRequest: Equatable, Sendable {
    public let url: URL
    /// The `ETag` the last answer carried, sent as `If-None-Match`.
    public let etag: String?
    /// The `Last-Modified` the last answer carried, sent as
    /// `If-Modified-Since`.
    public let lastModified: String?

    public init(url: URL, etag: String? = nil, lastModified: String? = nil) {
        self.url = url
        self.etag = etag
        self.lastModified = lastModified
    }
}

/// One exchange's answer: what the exchange said, the validators a later request
/// echoes back, and — when it did not succeed — why.
public struct RemoteFetchAnswer: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// The server answered with a body.
        case succeeded
        /// The server answered that the file is unchanged.
        case notModified
        /// The exchange did not produce a body: a transport failure, a
        /// non-success status, or a redirect the fetcher refused.
        case refused
    }

    public let status: Status
    /// The body, empty for anything but `.succeeded`.
    public let body: Data
    public let etag: String?
    public let lastModified: String?
    /// Where the exchange ended, after any redirects, so a redirect that left
    /// HTTPS is visible to the checks rather than only to the fetcher.
    public let finalURL: URL?
    /// Why the exchange refused.
    public let reason: String?

    public init(
        status: Status,
        body: Data = Data(),
        etag: String? = nil,
        lastModified: String? = nil,
        finalURL: URL? = nil,
        reason: String? = nil
    ) {
        self.status = status
        self.body = body
        self.etag = etag
        self.lastModified = lastModified
        self.finalURL = finalURL
        self.reason = reason
    }

    public static func succeeded(
        body: Data,
        etag: String? = nil,
        lastModified: String? = nil,
        finalURL: URL? = nil
    ) -> RemoteFetchAnswer {
        RemoteFetchAnswer(status: .succeeded, body: body, etag: etag, lastModified: lastModified, finalURL: finalURL)
    }

    public static func notModified(
        etag: String? = nil,
        lastModified: String? = nil,
        finalURL: URL? = nil
    ) -> RemoteFetchAnswer {
        RemoteFetchAnswer(status: .notModified, etag: etag, lastModified: lastModified, finalURL: finalURL)
    }

    public static func refused(_ reason: String, finalURL: URL? = nil) -> RemoteFetchAnswer {
        RemoteFetchAnswer(status: .refused, finalURL: finalURL, reason: reason)
    }
}

/// The seam the network sits behind. The application answers it with a real
/// exchange over the session it alone owns; the suite answers it with a script
/// and never reaches the network.
public protocol RemoteFetching: Sendable {
    func fetch(_ request: RemoteFetchRequest) async -> RemoteFetchAnswer
}
