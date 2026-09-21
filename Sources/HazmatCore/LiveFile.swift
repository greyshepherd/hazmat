import Foundation

/// What the live file holds for the block the store renders now.
public enum BlockState: Equatable, Sendable {
    /// No block: the next apply is a first apply.
    case absent
    /// The block is present and byte-identical to the rendered block.
    case unchanged
    /// The block is present and differs from the rendered block.
    case drifted
    /// The markers cannot be read as one block of a supported version.
    case refused(BlockError)

    /// Classifies `live` against the block the store renders now. Reading the
    /// file is the caller's business, so this is a function of bytes alone.
    public static func classify(live: Data, rendered: Data) -> BlockState {
        let location: ManagedBlockLocation
        do {
            guard let found = try ManagedBlock.locate(in: live) else { return .absent }
            location = found
        } catch let error as BlockError {
            return .refused(error)
        } catch {
            return .refused(.invalidBlock("\(error)"))
        }
        guard location.version == ManagedBlock.version else {
            return .refused(.unsupportedVersion(found: location.version, expected: ManagedBlock.version))
        }
        return Data(live[location.range]) == rendered ? .unchanged : .drifted
    }
}

/// The live hosts file, read on demand through an injected path.
public struct LiveHostsFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Reads the file now. Nothing is cached: every decision starts from these
    /// bytes, so a change made by another tool is seen rather than remembered.
    /// Read into pages of its own, so a file read on every refresh leaves no
    /// freed block behind each time.
    public func read() throws -> Data {
        try FileBytes.read(url)
    }

    public func state(rendered: Data) throws -> BlockState {
        BlockState.classify(live: try read(), rendered: rendered)
    }
}
