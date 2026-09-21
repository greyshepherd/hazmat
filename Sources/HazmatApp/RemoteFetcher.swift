import Foundation
import HazmatAppSupport
import HazmatCore

/// What one exchange decides as it runs: whether it may go to a URL at all,
/// whether it may follow a redirect, and whether the body has outgrown what the
/// store could hold. The rules are a value, so the delegate that runs an exchange
/// and a test that scripts one ask exactly the same questions.
public struct RemoteExchangeRules: Sendable {
    public let redirectLimit: Int
    public let bodyLimit: Int
    public let timeout: TimeInterval

    public static let standard = RemoteExchangeRules(
        redirectLimit: FetchBounds.redirectLimit,
        bodyLimit: FetchBounds.bodySizeBound,
        timeout: FetchBounds.exchangeTime
    )

    public init(redirectLimit: Int, bodyLimit: Int, timeout: TimeInterval) {
        self.redirectLimit = redirectLimit
        self.bodyLimit = bodyLimit
        self.timeout = timeout
    }

    /// Why a URL may not be fetched at all, or `nil` when it may. Asked before a
    /// request is made, so a plain-HTTP source never reaches the network.
    public func refusal(for url: URL?) -> String? {
        guard url?.scheme?.lowercased() != "https" else { return nil }
        let named = url?.absoluteString ?? "the request's URL"
        return "'\(named)' is not HTTPS; a source is fetched over HTTPS only"
    }

    /// Whether an exchange that has already followed `followed` redirects may
    /// follow one more, to `target`. A redirect that leaves HTTPS is not
    /// followed, and neither is one past the limit: refusing the redirect leaves
    /// the exchange with the answer it had rather than a body from elsewhere.
    public func follows(_ target: URL?, after followed: Int) -> Bool {
        followed < redirectLimit && refusal(for: target) == nil
    }

    /// Why a body of `received` bytes is refused, or `nil` while it is within the
    /// bound.
    public func bodyRefusal(received: Int) -> String? {
        guard received > bodyLimit else { return nil }
        return FetchBounds.oversizedBody(received)
    }
}

/// The application's only door to the network. Everything the core and app
/// support decide about a URL, an answer, and a body is decided again on the way
/// out: nothing but an HTTPS URL is requested, a redirect that leaves HTTPS is
/// refused, the request is conditional and bounded in time, and the body read
/// stops at the store's own bound rather than after it.
public struct URLSessionRemoteFetcher: RemoteFetching {
    public let rules: RemoteExchangeRules
    private let configuration: URLSessionConfiguration

    public init(rules: RemoteExchangeRules = .standard, configuration: URLSessionConfiguration? = nil) {
        self.rules = rules
        self.configuration = configuration ?? Self.defaultConfiguration
    }

    /// No cache, no cookies, no credentials: a source is one conditional request
    /// for a file anyone may read.
    public static var defaultConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        return configuration
    }

    public func fetch(_ request: RemoteFetchRequest) async -> RemoteFetchAnswer {
        if let reason = rules.refusal(for: request.url) {
            return .refused(reason)
        }

        let exchange = BoundedExchange(rules: rules)
        let session = URLSession(configuration: configuration, delegate: exchange, delegateQueue: nil)
        let answer = await exchange.run(urlRequest(for: request), on: session)
        // The session holds its delegate, and the delegate its continuation, so
        // the session is finished with once the answer is in hand.
        session.finishTasksAndInvalidate()
        return answer
    }

    /// The request as the exchange sends it: GET, conditional, and bounded in
    /// time.
    func urlRequest(for request: RemoteFetchRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = rules.timeout
        urlRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let etag = request.etag, !etag.isEmpty {
            urlRequest.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = request.lastModified, !lastModified.isEmpty {
            urlRequest.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        return urlRequest
    }
}

/// One exchange: it follows no redirect that leaves HTTPS, bounds how many it
/// follows, and stops keeping body bytes at the store's bound rather than after
/// it. The delegate callbacks arrive on a session's own queue, so the state they
/// share is behind a lock; the answer is handed back once.
private final class BoundedExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let rules: RemoteExchangeRules
    private let lock = NSLock()
    private var body = Data()
    private var response: HTTPURLResponse?
    private var followed = 0
    private var refusal: String?
    private var continuation: CheckedContinuation<RemoteFetchAnswer, Never>?
    private var task: URLSessionDataTask?
    private var cancellation: String?

    init(rules: RemoteExchangeRules) {
        self.rules = rules
    }

    func run(_ request: URLRequest, on session: URLSession) async -> RemoteFetchAnswer {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()

                let task = session.dataTask(with: request)
                lock.lock()
                self.task = task
                let cancelled = cancellation
                lock.unlock()

                task.resume()
                if cancelled != nil { task.cancel() }
            }
        } onCancel: {
            lock.lock()
            cancellation = "the exchange was cancelled"
            let task = self.task
            lock.unlock()
            task?.cancel()
        }
    }

    // MARK: URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            lock.lock()
            self.response = http
            lock.unlock()
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        if refusal == nil {
            body.append(data)
            if let reason = rules.bodyRefusal(received: body.count) {
                // The read stops here: the rest of the body is never kept.
                refusal = reason
                body = Data()
                lock.unlock()
                dataTask.cancel()
                return
            }
        }
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        let allowed = rules.follows(request.url, after: followed)
        if allowed { followed += 1 }
        lock.unlock()

        if allowed {
            completionHandler(request)
        } else {
            // Answering with no request stops the redirect: the exchange keeps
            // the response it had rather than following one it may not.
            completionHandler(nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let answer = self.answer(for: error)
        lock.unlock()

        continuation.resume(returning: answer)
    }

    /// The answer one finished exchange reports.
    private func answer(for error: Error?) -> RemoteFetchAnswer {
        if let cancellation { return .refused(cancellation) }
        if let refusal { return .refused(refusal, finalURL: response?.url) }
        if let error { return .refused("\(error)", finalURL: response?.url) }
        guard let response else { return .refused("the exchange produced no answer") }

        let etag = response.value(forHTTPHeaderField: "ETag")
        let lastModified = response.value(forHTTPHeaderField: "Last-Modified")
        switch response.statusCode {
        case 304:
            return .notModified(etag: etag, lastModified: lastModified, finalURL: response.url)
        case 200..<300:
            return .succeeded(body: body, etag: etag, lastModified: lastModified, finalURL: response.url)
        default:
            return .refused("the server answered \(response.statusCode)", finalURL: response.url)
        }
    }
}
