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
        call { proxy, reply in
            proxy.writeFileBytes(bytes, baselineDigest: BaselineDigest.of(baseline), withReply: reply)
        }
    }

    public func removeBlock(baseline: Data) -> PrivilegedWriteResult {
        call { proxy, reply in
            proxy.removeManagedBlock(BaselineDigest.of(baseline), withReply: reply)
        }
    }

    private func call(_ body: (HazmatDaemonXPC, @escaping (Int32, String?) -> Void) -> Void) -> PrivilegedWriteResult {
        let connection = NSXPCConnection(machServiceName: machServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: HazmatDaemonXPC.self)

        let box = ReplyBox()
        let answered = DispatchSemaphore(value: 0)
        connection.invalidationHandler = {
            box.finish(.failed(reason: "the helper is not running"))
            answered.signal()
        }
        connection.interruptionHandler = {
            box.finish(.failed(reason: "the connection to the helper was interrupted"))
            answered.signal()
        }
        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            box.finish(.failed(reason: "the helper is unreachable: \(error.localizedDescription)"))
            answered.signal()
        }) as? HazmatDaemonXPC else {
            connection.invalidate()
            return .failed(reason: "the helper did not expose its interface")
        }

        body(proxy) { status, reason in
            box.finish(Self.result(status: status, reason: reason))
            answered.signal()
        }

        if answered.wait(timeout: .now() + timeout) == .timedOut {
            box.finish(.failed(reason: "the helper did not answer in time"))
        }
        connection.invalidate()
        return box.value
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

/// First answer wins: the reply, the error handler, the interruption handler,
/// and the invalidation handler can all fire on the same request.
private final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: PrivilegedWriteResult?

    func finish(_ value: PrivilegedWriteResult) {
        lock.lock()
        defer { lock.unlock() }
        if result == nil {
            result = value
        }
    }

    var value: PrivilegedWriteResult {
        lock.lock()
        defer { lock.unlock() }
        return result ?? .failed(reason: "the helper gave no answer")
    }
}
