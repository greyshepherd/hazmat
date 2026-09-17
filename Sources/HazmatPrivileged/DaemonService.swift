import Foundation
import HazmatProtocol
import os

/// What the listener asks before exporting anything: does the process behind
/// this connection carry the identity the daemon trusts.
public protocol ConnectionVerifying: Sendable {
    func accepts(processIdentifier: pid_t) -> Bool
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

    func writeFileBytes(_ bytes: Data, baselineDigest: Data, withReply reply: @escaping (Int32, String?) -> Void) {
        let (status, reason) = handler.write(bytes: bytes, baselineDigest: baselineDigest)
        reply(status, reason)
    }

    func removeManagedBlock(_ baselineDigest: Data, withReply reply: @escaping (Int32, String?) -> Void) {
        let (status, reason) = handler.remove(baselineDigest: baselineDigest)
        reply(status, reason)
    }
}

/// Accepts a connection only when its process satisfies the code requirement,
/// then exports the handler over it.
public final class DaemonListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let handler: DaemonWriteHandler
    private let verifier: ConnectionVerifying
    private let logger: Logger

    public init(
        handler: DaemonWriteHandler,
        verifier: ConnectionVerifying,
        logger: Logger = Logger(subsystem: HazmatIdentity.bundleIdentifier, category: "daemon")
    ) {
        self.handler = handler
        self.verifier = verifier
        self.logger = logger
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let processIdentifier = connection.processIdentifier
        guard verifier.accepts(processIdentifier: processIdentifier) else {
            logger.error("refused a connection from process \(processIdentifier): it does not satisfy the daemon's code requirement")
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: HazmatDaemonXPC.self)
        connection.exportedObject = DaemonService(handler: handler)
        connection.resume()
        return true
    }
}
