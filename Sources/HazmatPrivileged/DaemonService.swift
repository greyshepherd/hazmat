import Foundation
import HazmatProtocol
import os

/// What the listener puts on a connection before exporting anything: the code
/// requirement the system checks the sender of every message against. A peer
/// that does not satisfy it never reaches the exported object.
public protocol ConnectionVerifying: Sendable {
    /// The requirement in the system's own language, or the reason it cannot
    /// be read. An unreadable requirement refuses the connection.
    func readableRequirement() throws -> String
}

extension SignatureVerifier: ConnectionVerifying {}

/// Turns a service outcome into the two values that cross the boundary: a status
/// and a reason.
public struct DaemonWriteHandler: Sendable {
    public let service: PrivilegedWriteService

    public init(service: PrivilegedWriteService) {
        self.service = service
    }

    public func write(bytes: Data, baselineDigest: Data) -> (Int32, String?) {
        reply(service.write(bytes: bytes, baselineDigest: baselineDigest))
    }

    public func remove(baselineDigest: Data) -> (Int32, String?) {
        reply(service.removeBlock(baselineDigest: baselineDigest))
    }

    private func reply(_ outcome: WriteOutcome) -> (Int32, String?) {
        switch outcome {
        case .written:
            return (HazmatWriteStatus.written.rawValue, nil)
        case .refused(let refusal):
            return (HazmatWriteStatus.refused.rawValue, refusal.description)
        case .failed(let reason):
            return (HazmatWriteStatus.failed.rawValue, reason)
        }
    }
}

/// The object the connection exports. Every reply is the handler's answer,
/// nothing else.
final class DaemonService: NSObject, HazmatDaemonXPC {
    private let handler: DaemonWriteHandler

    init(handler: DaemonWriteHandler) {
        self.handler = handler
    }

    /// The check answers as soon as the daemon is running: it has nothing to
    /// decide, so it reads nothing through the handler and touches no file.
    func checkIn(withReply reply: @escaping () -> Void) {
        reply()
    }

    func writeFileBytes(_ bytes: Data, baselineDigest: Data, withReply reply: @escaping (Int32, String?) -> Void) {
        let (status, reason) = handler.write(bytes: bytes, baselineDigest: baselineDigest)
        reply(status, reason)
    }

    func removeManagedBlock(_ baselineDigest: Data, withReply reply: @escaping (Int32, String?) -> Void) {
        let (status, reason) = handler.remove(baselineDigest: baselineDigest)
        reply(status, reason)
    }
}

/// Puts the code requirement on every connection and exports the handler over
/// it. The requirement is checked by the system against the audit token of each
/// message's sender, not by this code against a process identifier at accept
/// time, so a process that is replaced after connecting does not keep its access.
public final class DaemonListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let handler: DaemonWriteHandler
    private let verifier: ConnectionVerifying
    private let logger: Logger
    /// Nothing keeps the daemon alive between requests when this is set, so the
    /// build on disk is the one that serves the next request.
    private let idleExit: IdleExit?

    public init(
        handler: DaemonWriteHandler,
        verifier: ConnectionVerifying,
        idleExit: IdleExit? = nil,
        logger: Logger = Logger(subsystem: HazmatIdentity.bundleIdentifier, category: "daemon")
    ) {
        self.handler = handler
        self.verifier = verifier
        self.idleExit = idleExit
        self.logger = logger
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let requirement: String
        do {
            requirement = try verifier.readableRequirement()
        } catch {
            logger.error("refused a connection: the daemon's code requirement cannot be read (\(error))")
            return false
        }
        connection.setCodeSigningRequirement(requirement)
        idleExit?.connectionOpened()
        // Interruption and invalidation can both arrive for one connection, and
        // either way the client is gone.
        let gone = Once()
        connection.invalidationHandler = { [idleExit] in
            if gone.claim() { idleExit?.connectionClosed() }
        }
        connection.interruptionHandler = { [idleExit] in
            if gone.claim() { idleExit?.connectionClosed() }
        }
        connection.exportedInterface = NSXPCInterface(with: HazmatDaemonXPC.self)
        connection.exportedObject = DaemonService(handler: handler)
        connection.resume()
        return true
    }
}

/// Whether the first of two callbacks has already been taken.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
