import Foundation
import HazmatCore

/// Why a typed URL cannot be a source's origin: the sentence a field shows. An
/// error rather than a bare `String`, so `Result` can carry it.
public struct URLRefusal: Error, Equatable, Sendable, CustomStringConvertible {
    public let reason: String

    public init(_ reason: String) {
        self.reason = reason
    }

    public var description: String { reason }
}

/// What one refresh did, and the source as it stands afterwards.
public struct RemoteRefresh: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The fetched text differs from the fragment's, and the store now holds
        /// it.
        case wrote
        /// The answer carried no change: the fragment's bytes and modification
        /// time are untouched.
        case unchanged
        /// The fetch or the write was refused. The fragment keeps the text it
        /// had.
        case refused(reason: String)
    }

    public let fragment: FragmentID
    public let outcome: Outcome
    /// The source as recorded after the attempt: the attempt and its outcome,
    /// with the previous text's validators kept when the refresh failed.
    public let source: RemoteSource

    public init(fragment: FragmentID, outcome: Outcome, source: RemoteSource) {
        self.fragment = fragment
        self.outcome = outcome
        self.source = source
    }

    /// Whether the store gained new text.
    public var didWrite: Bool { outcome == .wrote }

    /// Whether the refresh did not do what it set out to do.
    public var wasRefused: Bool {
        if case .refused = outcome { return true }
        return false
    }

    /// Why the refresh was refused, when it was.
    public var reason: String? {
        guard case .refused(let reason) = outcome else { return nil }
        return reason
    }

    public var description: String {
        switch outcome {
        case .wrote: return "the source fetched new text"
        case .unchanged: return "the source is unchanged"
        case .refused(let reason): return "the source was not refreshed: \(reason)"
        }
    }
}

/// Fetches a source and stores what came back, deciding everything the network
/// is not allowed to decide: what a URL and an answer must be, what a body may
/// hold, and what is written when.
///
/// A refresh is the same operation as an edit as far as the store is concerned —
/// the text goes through `StoreWriter` — and it only ever writes the fragment
/// and its own sidecar. A refusal happens before anything is written, so a
/// refused answer leaves the fragment exactly as it was.
public struct RemoteRefresher: Sendable {
    public let layout: StoreLayout
    public let writer: StoreWriter
    public let fetcher: any RemoteFetching

    public init(layout: StoreLayout, writer: StoreWriter? = nil, fetcher: any RemoteFetching) {
        self.layout = layout
        self.writer = writer ?? StoreWriter(layout: layout)
        self.fetcher = fetcher
    }

    public init(layout: StoreLayout, fetcher: any RemoteFetching) {
        self.init(layout: layout, writer: nil, fetcher: fetcher)
    }

    /// Fetches `fragment`'s source and stores what came back. `now` is the
    /// moment the attempt is recorded as, so a test can drive the schedule.
    public func refresh(
        fragment: FragmentID,
        source: RemoteSource,
        at now: Date = Date()
    ) async -> RemoteRefresh {
        if let reason = Self.httpsRefusal(source.url) {
            return record(fragment, source, outcome: .refused(reason: reason), at: now)
        }

        let answer = await fetcher.fetch(
            RemoteFetchRequest(url: source.url, etag: source.etag, lastModified: source.lastModified)
        )

        if let reason = Self.refusal(of: answer, fragment: fragment) {
            return record(fragment, source, outcome: .refused(reason: reason), at: now)
        }

        switch answer.status {
        case .notModified:
            // The answer said the file is unchanged, so the fragment is not
            // rewritten and its modification time stays honest.
            return record(fragment, source, outcome: .unchanged, at: now, validators: answer)

        case .succeeded:
            if let existing = try? Data(contentsOf: layout.fragmentURL(fragment)), existing == answer.body {
                return record(fragment, source, outcome: .unchanged, at: now, validators: answer)
            }
            do {
                try writer.save(String(decoding: answer.body, as: UTF8.self), asFragment: fragment)
            } catch {
                return record(fragment, source, outcome: .refused(reason: "\(error)"), at: now)
            }
            return record(fragment, source, outcome: .wrote, at: now, validators: answer)

        case .refused:
            let reason = answer.reason ?? "the exchange was refused"
            return record(fragment, source, outcome: .refused(reason: reason), at: now)
        }
    }

    // MARK: - What a fetch refuses

    /// Why a URL may not be fetched, or `nil` when it may. The same answer the
    /// window reports when a source is added with a URL that is not HTTPS, so
    /// nothing is recorded for a URL that could never be fetched.
    public static func httpsRefusal(_ url: URL?) -> String? {
        guard !isHTTPS(url) else { return nil }
        return notHTTPSRefusal(naming: url?.absoluteString ?? "that URL")
    }

    /// Whether the exchange may go to this URL at all.
    private static func isHTTPS(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https"
    }

    /// What is wrong with a URL that is not HTTPS, as a clause: it reads as well
    /// after a URL as after "redirected to …", which a whole sentence does not.
    private static let notHTTPS = "is not an HTTPS URL"

    /// The refusal, naming the URL as it was given.
    private static func notHTTPSRefusal(naming subject: String) -> String {
        "'\(subject)' \(notHTTPS). A source is fetched over HTTPS only."
    }

    /// The URL a typed field names, or why it cannot be one. One call answers both
    /// for a caller that needs the URL, so a field is parsed once and the refusal
    /// it would get is the same sentence the field shows.
    ///
    /// A refusal quotes what was typed rather than what Foundation made of it: a
    /// typed `not a url` would otherwise be reported back as `not%20a%20url`.
    public static func origin(from text: String) -> Result<URL, URLRefusal> {
        guard let parsed = URL(string: text) else {
            return .failure(URLRefusal("'\(text)' is not a URL. Paste the address you would open in a browser."))
        }
        guard isHTTPS(parsed) else {
            return .failure(URLRefusal(notHTTPSRefusal(naming: text)))
        }
        return .success(parsed)
    }

    /// Why what was typed into a URL field cannot be a source's origin, or `nil`
    /// when it can.
    public static func urlRefusal(_ text: String) -> String? {
        guard case .failure(let refusal) = origin(from: text) else { return nil }
        return refusal.reason
    }

    /// Why an answer may not be stored, or `nil` when it may. Ordered so the most
    /// specific reason wins: where the exchange landed, then what it said, then
    /// what it carried.
    static func refusal(of answer: RemoteFetchAnswer, fragment: FragmentID) -> String? {
        if let finalURL = answer.finalURL, httpsRefusal(finalURL) != nil {
            // The redirect's own sentence: composing the URL refusal here read as
            // "redirected to 'http://…' is not an HTTPS URL".
            return "the exchange was redirected to '\(finalURL.absoluteString)', which \(Self.notHTTPS)."
        }

        switch answer.status {
        case .refused:
            return answer.reason ?? "the exchange was refused"
        case .notModified:
            return nil
        case .succeeded:
            break
        }

        guard answer.body.count <= FetchBounds.bodySizeBound else {
            return FetchBounds.oversizedBody(answer.body.count)
        }
        guard let text = String(bytes: answer.body, encoding: .utf8) else {
            return "the body is not valid UTF-8"
        }
        guard !FragmentParser.parse(text, as: fragment).carriesDirective else {
            return "the body carries a hazmat: directive, which a fetched file may not do"
        }
        return nil
    }

    // MARK: - Recording
    /// Records the attempt and its outcome in the sidecar. A refresh that failed
    /// keeps the previous text's validators: they still describe the text the
    /// fragment holds. A recorded state that cannot be written is reported, so a
    /// refresh never claims a success the store does not hold.
    private func record(
        _ fragment: FragmentID,
        _ source: RemoteSource,
        outcome: RemoteRefresh.Outcome,
        at now: Date,
        validators answer: RemoteFetchAnswer? = nil
    ) -> RemoteRefresh {
        var updated = source
        updated.lastAttempt = now
        switch outcome {
        case .wrote, .unchanged:
            updated.lastSuccess = now
            updated.lastFailure = nil
            if let answer {
                updated.etag = answer.etag ?? source.etag
                updated.lastModified = answer.lastModified ?? source.lastModified
            }
        case .refused:
            updated.lastFailure = outcome.reason
        }

        do {
            try writer.save(updated, as: fragment)
        } catch {
            // The fragment's own text is written by its own call and is never
            // half-written, so a failed record leaves the previous text readable
            // either way. Report the record's failure rather than a success the
            // store cannot show.
            let reason = "the source's state could not be recorded: \(error)"
            return RemoteRefresh(fragment: fragment, outcome: .refused(reason: reason), source: source)
        }

        return RemoteRefresh(fragment: fragment, outcome: outcome, source: updated)
    }
}

private extension RemoteRefresh.Outcome {
    var reason: String? {
        guard case .refused(let reason) = self else { return nil }
        return reason
    }
}
