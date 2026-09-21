import Foundation

/// What the caller expects to find in the live file, and therefore what an
/// apply may replace. The expectation is the caller's proof: an apply replaces a
/// block only when it is the one named here, byte for byte.
public enum Replacement: Equatable, Sendable {
    /// Write only where the file holds no block.
    case onlyIfAbsent
    /// Replace the block with this digest, which the caller read and intends to
    /// replace. The digest names the bytes; the apply reads them again itself.
    case block(ByteDigest)
}

/// What an apply did, and the bytes it replaced when it replaced any. The
/// caller named the replaced block by its digest and need never have held its
/// bytes; the apply read them, so it is the apply that hands them back to
/// whoever keeps them for a revert.
public struct ApplyResult: Equatable, Sendable {
    public let outcome: ApplyOutcome
    public let replaced: Data?

    public init(outcome: ApplyOutcome, replaced: Data? = nil) {
        self.outcome = outcome
        self.replaced = replaced
    }
}

/// How an apply changed the file.
public enum AppliedChange: Equatable, Sendable {
    case installedBlock
    case replacedBlock(overwroteDrift: Bool)
    case removedBlock
}

/// Why an apply was refused. Refusal is a decision made before writing.
public enum ApplyRefusal: Equatable, Sendable, CustomStringConvertible {
    /// The live block is not the one the caller named, or the caller named no
    /// block while the file holds one. Either way the difference is drift and
    /// nothing is written.
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
            return "the live block is not the one this apply expects; the difference is drift and it was left alone"
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

    /// Installs `block` at `position`. The replacement carries the caller's
    /// expectation: no block at all, or the exact block it read and intends to
    /// replace.
    public func apply(
        block: Data,
        position: BlockPosition = .default,
        replacement: Replacement = .onlyIfAbsent
    ) -> ApplyOutcome {
        applyReporting(block: block, position: position, replacement: replacement).outcome
    }

    /// The same apply, reporting the bytes of the block it replaced.
    public func applyReporting(
        block: Data,
        position: BlockPosition = .default,
        replacement: Replacement = .onlyIfAbsent
    ) -> ApplyResult {
        let live: Data
        do {
            live = try file.read()
        } catch {
            return ApplyResult(outcome: .failed(reason: "reading \(file.url.path): \(error)"))
        }

        let present: Data?
        do {
            if let location = try ManagedBlock.locate(in: live) {
                guard location.version == ManagedBlock.version else {
                    return ApplyResult(outcome: .refused(.liveFile(.unsupportedVersion(found: location.version, expected: ManagedBlock.version))))
                }
                present = Data(live[location.range])
            } else {
                present = nil
            }
        } catch let error as BlockError {
            return ApplyResult(outcome: .refused(.liveFile(error)))
        } catch {
            return ApplyResult(outcome: .refused(.liveFile(.invalidBlock("\(error)"))))
        }

        if present == block { return ApplyResult(outcome: .nothingToDo) }

        switch (present, replacement) {
        case (nil, .onlyIfAbsent):
            break
        case (nil, .block):
            // Nothing to replace, so the caller's expectation cannot hold.
            return ApplyResult(outcome: .refused(.driftNotOverwritten))
        case (.some, .onlyIfAbsent):
            return ApplyResult(outcome: .refused(.driftNotOverwritten))
        case (.some(let liveBlock), .block(let expected)):
            guard ByteDigest(liveBlock) == expected else { return ApplyResult(outcome: .refused(.driftNotOverwritten)) }
        }

        let planned: Data
        do {
            planned = try BlockSplice.splice(block: block, into: live, at: position)
        } catch let error as BlockError {
            return ApplyResult(outcome: .refused(.unusableBlock(.block(error))))
        } catch {
            return ApplyResult(outcome: .failed(reason: "planning the write: \(error)"))
        }

        switch PlanVerification.check(planned: planned, live: live) {
        case .ok:
            break
        case .refused(let refusal):
            return ApplyResult(outcome: .refused(.unusableBlock(refusal)))
        case .bytesOutsideBlockChanged:
            return ApplyResult(outcome: .refused(.bytesOutsideBlockChanged))
        }

        guard planned != live else { return ApplyResult(outcome: .nothingToDo) }

        switch writer.write(bytes: planned, baseline: live) {
        case .written:
            return ApplyResult(
                outcome: .applied(present == nil ? .installedBlock : .replacedBlock(overwroteDrift: true)),
                replaced: present
            )
        case .refused(let reason):
            return ApplyResult(outcome: .refused(.privileged(reason)))
        case .failed(let reason):
            return ApplyResult(outcome: .failed(reason: reason))
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
