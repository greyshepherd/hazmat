import Foundation
import HazmatCore
import HazmatProtocol

/// Asking whether the helper is there, so the window's state can rest on an
/// answer rather than on the registration alone.
public protocol HelperPresence: Sendable {
    /// Whether the helper answered, and how. Bounded: a helper the system can no
    /// longer start answers nothing, so this returns rather than waits.
    func check() -> HelperReachability
}

/// The app's side of the privileged boundary: one connection per request, so
/// there is no shared connection state to guard.
public final class DaemonClient: PrivilegedWriter, HelperPresence, @unchecked Sendable {
    /// A write is an atomic replacement of one file, so a helper that answers
    /// answers in milliseconds. Reaching this bound means the helper was never
    /// started, which is a state the user can repair; the report says so.
    public static let writeBoundSeconds = 10
    /// A check has nothing to do but answer, so it needs far less room than a
    /// write. The bound is only ever reached when nothing is there to answer.
    public static let presenceBoundSeconds = 3

    private let connectionFor: @Sendable () -> NSXPCConnection
    private let writeBoundSeconds: Int
    private let presenceBoundSeconds: Int

    public convenience init(
        machServiceName: String = HazmatIdentity.machServiceName,
        writeBoundSeconds: Int = DaemonClient.writeBoundSeconds,
        presenceBoundSeconds: Int = DaemonClient.presenceBoundSeconds
    ) {
        self.init(
            connectionFor: { NSXPCConnection(machServiceName: machServiceName, options: []) },
            writeBoundSeconds: writeBoundSeconds,
            presenceBoundSeconds: presenceBoundSeconds
        )
    }

    /// How a request reaches the helper. The app's answer is one connection to
    /// the mach service; a test's answer is a connection to a listener it holds,
    /// so the whole boundary can be exercised without a daemon and without root.
    public init(
        connectionFor: @escaping @Sendable () -> NSXPCConnection,
        writeBoundSeconds: Int = DaemonClient.writeBoundSeconds,
        presenceBoundSeconds: Int = DaemonClient.presenceBoundSeconds
    ) {
        self.connectionFor = connectionFor
        self.writeBoundSeconds = writeBoundSeconds
        self.presenceBoundSeconds = presenceBoundSeconds
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

    /// Whether the helper answers. A reply is the whole answer, so a helper that
    /// is running but rejects this app is reported as refusing rather than as
    /// silent: the two read the same in the window but the notice quotes the
    /// system's own words.
    public func check() -> HelperReachability {
        let connection = connectionFor()
        connection.remoteObjectInterface = NSXPCInterface(with: HazmatDaemonXPC.self)

        let box = PresenceBox()
        let answered = DispatchSemaphore(value: 0)
        connection.invalidationHandler = {
            box.finish(.refused(reason: "the helper is not running"))
            answered.signal()
        }
        connection.interruptionHandler = {
            box.finish(.refused(reason: "the connection to the helper was interrupted"))
            answered.signal()
        }
        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            box.finish(.refused(reason: "the helper is unreachable: \(error.localizedDescription)"))
            answered.signal()
        }) as? HazmatDaemonXPC else {
            connection.invalidate()
            return .refused(reason: "the helper did not expose its interface")
        }

        proxy.checkIn {
            box.finish(.answering)
            answered.signal()
        }

        if answered.wait(timeout: .now() + .seconds(presenceBoundSeconds)) == .timedOut {
            box.finish(.silent)
        }
        connection.invalidate()
        return box.value
    }

    /// A write is made once more when the connection died before the bound: the
    /// daemon stops when it has nothing to serve, so a request that lands while
    /// it stops finds nothing listening, and launchd starts the installed build
    /// for the next message.
    private func answer(_ attempt: () -> Attempt) -> PrivilegedWriteResult {
        attemptedTwice(attempt).result
    }

    private func call(_ body: (HazmatDaemonXPC, @escaping (Int32, String?) -> Void) -> Void) -> Attempt {
        let connection = connectionFor()
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

        if answered.wait(timeout: .now() + .seconds(writeBoundSeconds)) == .timedOut {
            box.finish(Self.unanswered(within: writeBoundSeconds))
        }
        connection.invalidate()
        return box.attempt
    }

    /// The words the window shows when nothing answered: what happened, and the
    /// action that puts it right.
    private static func unanswered(within seconds: Int) -> PrivilegedWriteResult {
        .failed(
            reason: "the helper did not answer within \(seconds) seconds, so it may not have started. "
                + "Repair the helper to register it again."
        )
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

/// One exchange with the helper: its answer, or a connection that died before
/// there was one. Only the second is worth repeating — a helper that was given
/// its whole bound and said nothing is a state to report, not to ask again.
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

/// Repeats a request once when the connection died before an answer, so a request
/// that lands as the daemon stops is answered by the one launchd starts. An
/// answer — including the one that reports a bound was reached — is never
/// repeated.
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

    /// A connection that died on its own, which is the repeatable case, as
    /// opposed to a helper that was asked and gave its bound away.
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

/// The same rule for a check: the answer, the handlers, and the bound can each
/// arrive on their own thread, and only the first one counts.
private final class PresenceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: HelperReachability?

    func finish(_ value: HelperReachability) {
        lock.lock()
        defer { lock.unlock() }
        if result == nil {
            result = value
        }
    }

    var value: HelperReachability {
        lock.lock()
        defer { lock.unlock() }
        return result ?? .silent
    }
}
