import Foundation

/// What the privileged side reports back. A refusal is a decision; a failure is
/// the machine getting in the way.
public enum PrivilegedWriteResult: Equatable, Sendable {
    case written
    case refused(reason: String)
    case failed(reason: String)
}

/// The client side of the privilege boundary. The core stays free of the
/// transport: the app carries these over XPC, a test records them.
public protocol PrivilegedWriter: Sendable {
    /// Installs finished bytes, refusing when the live file no longer matches
    /// `baseline`. Implementations carry a digest of `baseline` across.
    func write(bytes: Data, baseline: Data) -> PrivilegedWriteResult

    /// Removes the managed block from the live file, refusing on the same terms.
    /// The bytes are never sent: the privileged side strips the block itself.
    func removeBlock(baseline: Data) -> PrivilegedWriteResult
}
