import Foundation
import HazmatCore
import HazmatProtocol

/// Why the privileged side refused a write. Refusing is a decision; nothing is
/// written when one is returned.
public enum WriteRefusal: Equatable, Sendable, CustomStringConvertible {
    case oversized(actual: Int, bound: Int)
    case noBlock
    case block(BlockError)
    /// The file no longer holds the bytes the plan was based on.
    case baselineMismatch
    case accessControlList(String)

    init(_ refusal: ByteRefusal) {
        switch refusal {
        case .oversized(let actual, let bound):
            self = .oversized(actual: actual, bound: bound)
        case .noBlock:
            self = .noBlock
        case .block(let error):
            self = .block(error)
        }
    }

    public var description: String {
        switch self {
        case .oversized(let actual, let bound):
            return "the file is \(actual) bytes; the bound is \(bound)"
        case .noBlock:
            return "the bytes hold no managed block"
        case .block(let error):
            return error.description
        case .baselineMismatch:
            return "the file changed since it was read; the write was planned from other bytes"
        case .accessControlList(let detail):
            return "the file carries an access-control list: \(detail)"
        }
    }
}

public enum WriteOutcome: Equatable, Sendable {
    case written
    case refused(WriteRefusal)
    case failed(reason: String)

    public var description: String {
        switch self {
        case .written:
            return "written"
        case .refused(let refusal):
            return "refused: \(refusal)"
        case .failed(let reason):
            return "failed: \(reason)"
        }
    }
}

/// The privileged side's whole job: validate the bytes, check the file is still
/// the one the plan was based on, and replace it atomically. It composes
/// nothing, resolves nothing, and builds no path from a request.
public struct PrivilegedWriteService: Sendable {
    public let writer: AtomicFileWriter

    public init(target: URL, owner: FileOwnership = .system) {
        writer = AtomicFileWriter(target: target, owner: owner)
    }

    public init(writer: AtomicFileWriter) {
        self.writer = writer
    }

    /// Installs finished bytes.
    public func write(bytes: Data, baselineDigest: Data) -> WriteOutcome {
        if let refusal = PlannedBytes.refusal(bytes) {
            return .refused(WriteRefusal(refusal))
        }
        switch liveFile(matching: baselineDigest) {
        case .outcome(let outcome):
            return outcome
        case .file:
            break
        }
        return perform { try writer.write(bytes) }
    }

    /// Removes the managed block from the live file. The bytes are read here, so
    /// a removal can only ever take the block out of the file the plan was based
    /// on.
    public func removeBlock(baselineDigest: Data) -> WriteOutcome {
        let live: Data
        switch liveFile(matching: baselineDigest) {
        case .file(let bytes):
            live = bytes
        case .outcome(let outcome):
            return outcome
        }

        if let refusal = PlannedBytes.refusal(live) {
            return .refused(WriteRefusal(refusal))
        }
        let stripped: Data
        do {
            stripped = try BlockSplice.strip(from: live)
        } catch let error as BlockError {
            return .refused(.block(error))
        } catch {
            return .failed(reason: "stripping the block: \(error)")
        }
        guard stripped != live else {
            return .refused(.noBlock)
        }
        return perform { try writer.write(stripped) }
    }

    private enum LiveFile {
        case file(Data)
        case outcome(WriteOutcome)
    }

    /// The file the plan was based on, or the outcome to report instead.
    private func liveFile(matching baselineDigest: Data) -> LiveFile {
        let live: Data
        do {
            live = try Data(contentsOf: writer.target)
        } catch let error as NSError where error.code == NSFileReadNoSuchFileError {
            return .outcome(.refused(.baselineMismatch))
        } catch {
            return .outcome(.failed(reason: "reading \(writer.target.path): \(error)"))
        }
        guard BaselineDigest.of(live) == baselineDigest else {
            return .outcome(.refused(.baselineMismatch))
        }
        return .file(live)
    }

    private func perform(_ body: () throws -> Void) -> WriteOutcome {
        do {
            try body()
            return .written
        } catch let failure as WriteFailure {
            if case .accessControlList(let path) = failure {
                return .refused(.accessControlList(path))
            }
            return .failed(reason: failure.description)
        } catch {
            return .failed(reason: "\(error)")
        }
    }
}
