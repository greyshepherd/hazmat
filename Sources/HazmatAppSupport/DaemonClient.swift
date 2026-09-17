import Foundation
import HazmatCore
import HazmatProtocol

/// The app's side of the privileged boundary: one connection per request, so
/// there is no shared connection state to guard.
public final class DaemonClient: PrivilegedWriter, @unchecked Sendable {
    private let machServiceName: String
    private let timeout: DispatchTimeInterval

    public init(
        machServiceName: String = HazmatIdentity.machServiceName,
        timeout: DispatchTimeInterval = .seconds(30)
    ) {
        self.machServiceName = machServiceName
        self.timeout = timeout
    }

    public func write(bytes: Data, baseline: Data) -> PrivilegedWriteResult {
        answer {
            call { proxy, reply in
                proxy.writeFileBytes(bytes, baselineDigest: BaselineDigest.of(baseline), withReply: reply)
            }
        }
    }

    public func removeBlock(baseline: Data) -> PrivilegedWriteResult {
        answer {
            call { proxy, reply in
                proxy.removeManagedBlock(BaselineDigest.of(baseline), withReply: reply)
            }
        }
    }

    private func answer(_ attempt: () -> Attempt) -> PrivilegedWriteResult {
        attemptedTwice(attempt).result
    }

    private func call(_ body: (HazmatDaemonXPC, @escaping (Int32, String?) -> Void) -> Void) -> Attempt {
        let connection = NSXPCConnection(machServiceName: machServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: HazmatDaemonXPC.self)

        let box = ReplyBox()
        let answered = DispatchSemaphore(value: 0)
        connection.invalidationHandler = {
            box.lost(reason: "the helper is not running")
            answered.signal()
        }
        connection.interruptionHandler = {
            box.lost(reason: "the connection to the helper was interrupted")
            answered.signal()
        }
        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            box.lost(reason: "the helper is unreachable: \(error.localizedDescription)")
            answered.signal()
        }) as? HazmatDaemonXPC else {
            connection.invalidate()
            return .noReply(reason: "the helper did not expose its interface")
        }

        body(proxy) { status, reason in
            box.finish(Self.result(status: status, reason: reason))
            answered.signal()
        }

        if answered.wait(timeout: .now() + timeout) == .timedOut {
            box.lost(reason: "the helper did not answer in time")
        }
        connection.invalidate()
        return box.attempt
    }

    private static func result(status: Int32, reason: String?) -> PrivilegedWriteResult {
        switch HazmatWriteStatus(rawValue: status) {
        case .written:
            return .written
        case .refused:
            return .refused(reason: reason ?? "refused without a reason")
        case .failed:
            return .failed(reason: reason ?? "failed without a reason")
        case nil:
            return .failed(reason: "the helper replied with status \(status)")
        }
    }
}

/// The daemon stops when it has nothing to serve, so a request that arrives as it
/// stops finds nothing listening. launchd starts the installed build for the next
/// message, so that request is made once more. A refusal is an answer, and an
/// answer is never repeated.
func attemptedTwice(_ attempt: () -> Attempt) -> Attempt {
    switch attempt() {
    case .answer(let result):
        return .answer(result)
    case .noReply(let reason):
        switch attempt() {
        case .answer(let result): return .answer(result)
        case .noReply: return .noReply(reason: reason)
        }
    }
}

/// One exchange with the daemon: the daemon's answer, or a connection that died
/// before there was one.
enum Attempt: Equatable {
    case answer(PrivilegedWriteResult)
    case noReply(reason: String)

    var result: PrivilegedWriteResult {
        switch self {
        case .answer(let result): return result
        case .noReply(let reason): return .failed(reason: reason)
        }
    }
}

/// First answer wins: the reply, the error handler, the interruption handler,
/// and the invalidation handler can all fire on the same request.
private final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var answer: PrivilegedWriteResult?
    private var lostReason: String?

    func finish(_ value: PrivilegedWriteResult) {
        lock.lock()
        defer { lock.unlock() }
        if answer == nil && lostReason == nil {
            answer = value
        }
    }

    /// A connection that died, which is retryable, as opposed to a refusal.
    func lost(reason: String) {
        lock.lock()
        defer { lock.unlock() }
        if answer == nil && lostReason == nil {
            lostReason = reason
        }
    }

    var attempt: Attempt {
        lock.lock()
        defer { lock.unlock() }
        if let answer { return .answer(answer) }
        return .noReply(reason: lostReason ?? "the helper gave no answer")
    }
}
