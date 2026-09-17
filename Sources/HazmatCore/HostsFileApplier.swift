import Foundation

/// How an apply changed the file.
public enum AppliedChange: Equatable, Sendable {
    case installedBlock
    case replacedBlock(overwroteDrift: Bool)
    case removedBlock
}

/// Why an apply was refused. Refusal is a decision made before writing.
public enum ApplyRefusal: Equatable, Sendable, CustomStringConvertible {
    /// The live block differs from the rendered block and the caller did not ask
    /// for it to be overwritten.
    case driftNotOverwritten
    /// The live file's markers cannot be read as one supported block.
    case liveFile(BlockError)
    /// The bytes that would be written do not satisfy the byte contract.
    case unusableBlock(ByteRefusal)
    /// Removing the block would change bytes outside it.
    case bytesOutsideBlockChanged
    /// The privileged side refused; its reason is carried through.
    case privileged(String)

    public var description: String {
        switch self {
        case .driftNotOverwritten:
            return "the block in the live file differs from the rendered block; overwriting it was not asked for"
        case .liveFile(let error):
            return "the live file is refused: \(error)"
        case .unusableBlock(let refusal):
            return "the planned bytes are refused: \(refusal)"
        case .bytesOutsideBlockChanged:
            return "the planned bytes would change bytes outside the block"
        case .privileged(let reason):
            return "the privileged side refused: \(reason)"
        }
    }
}

/// Every apply reports exactly one of these, with a cause for the last two.
public enum ApplyOutcome: Equatable, Sendable {
    case nothingToDo
    case applied(AppliedChange)
    case refused(ApplyRefusal)
    case failed(reason: String)

    public var description: String {
        switch self {
        case .nothingToDo:
            return "nothing to do"
        case .applied(.installedBlock):
            return "applied: the block was installed"
        case .applied(.replacedBlock(let overwroteDrift)):
            return overwroteDrift ? "applied: drift was overwritten" : "applied: the block was replaced"
        case .applied(.removedBlock):
            return "applied: the block was removed"
        case .refused(let refusal):
            return "refused: \(refusal)"
        case .failed(let reason):
            return "failed: \(reason)"
        }
    }

    public var isApplied: Bool {
        if case .applied = self { return true }
        return false
    }
}

/// What the client proved before handing bytes to the privileged side.
public enum PlanCheck: Equatable, Sendable {
    case ok
    case refused(ByteRefusal)
    case bytesOutsideBlockChanged
}

/// The two checks that make a write safe: the planned bytes hold exactly one
/// well-formed block of a supported version, and removing that block restores
/// the bytes that were read.
public enum PlanVerification {
    public static func check(planned: Data, live: Data) -> PlanCheck {
        if let refusal = PlannedBytes.refusal(planned) {
            return .refused(refusal)
        }
        let strippedPlanned: Data
        let strippedLive: Data
        do {
            strippedPlanned = try BlockSplice.strip(from: planned)
            strippedLive = try BlockSplice.strip(from: live)
        } catch let error as BlockError {
            return .refused(.block(error))
        } catch {
            return .refused(.block(.invalidBlock("\(error)")))
        }
        return strippedPlanned == strippedLive ? .ok : .bytesOutsideBlockChanged
    }
}

/// Reads the live file, decides what to write, proves it, and hands it to the
/// privileged side. The path and the writer are injected, so everything here is
/// testable without privilege and without the real hosts file.
public struct HostsFileApplier: Sendable {
    public let file: LiveHostsFile
    public let writer: PrivilegedWriter

    public init(fileURL: URL, writer: PrivilegedWriter) {
        self.file = LiveHostsFile(url: fileURL)
        self.writer = writer
    }

    /// The live file's block state for the rendered block, without writing.
    public func state(rendered: Data) throws -> BlockState {
        try file.state(rendered: rendered)
    }

    /// Installs `block` at `position`, replacing a drifted block only when the
    /// caller asks for that.
    public func apply(block: Data, position: BlockPosition = .default, overwriteDrift: Bool = false) -> ApplyOutcome {
        let live: Data
        do {
            live = try file.read()
        } catch {
            return .failed(reason: "reading \(file.url.path): \(error)")
        }

        let state = BlockState.classify(live: live, rendered: block)
        switch state {
        case .refused(let error):
            return .refused(.liveFile(error))
        case .unchanged:
            return .nothingToDo
        case .drifted where !overwriteDrift:
            return .refused(.driftNotOverwritten)
        case .absent, .drifted:
            break
        }

        let planned: Data
        do {
            planned = try BlockSplice.splice(block: block, into: live, at: position)
        } catch let error as BlockError {
            return .refused(.unusableBlock(.block(error)))
        } catch {
            return .failed(reason: "planning the write: \(error)")
        }

        switch PlanVerification.check(planned: planned, live: live) {
        case .ok:
            break
        case .refused(let refusal):
            return .refused(.unusableBlock(refusal))
        case .bytesOutsideBlockChanged:
            return .refused(.bytesOutsideBlockChanged)
        }

        guard planned != live else { return .nothingToDo }

        switch writer.write(bytes: planned, baseline: live) {
        case .written:
            return .applied(state == .drifted ? .replacedBlock(overwroteDrift: true) : .installedBlock)
        case .refused(let reason):
            return .refused(.privileged(reason))
        case .failed(let reason):
            return .failed(reason: reason)
        }
    }

    /// Removes the managed block, leaving every byte outside it untouched.
    public func removeBlock() -> ApplyOutcome {
        let live: Data
        do {
            live = try file.read()
        } catch {
            return .failed(reason: "reading \(file.url.path): \(error)")
        }

        let stripped: Data
        do {
            stripped = try BlockSplice.strip(from: live)
        } catch let error as BlockError {
            return .refused(.liveFile(error))
        } catch {
            return .failed(reason: "stripping the block: \(error)")
        }
        guard stripped != live else { return .nothingToDo }

        switch writer.removeBlock(baseline: live) {
        case .written:
            return .applied(.removedBlock)
        case .refused(let reason):
            return .refused(.privileged(reason))
        case .failed(let reason):
            return .failed(reason: reason)
        }
    }
}
