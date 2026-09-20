import Foundation

/// Why finished bytes were refused. The same answer is used on both sides of the
/// privilege boundary, so a refusal reads the same wherever it happens.
public enum ByteRefusal: Error, Equatable, Sendable, CustomStringConvertible {
    case oversized(actual: Int, bound: Int)
    case noBlock
    case block(BlockError)

    public var description: String {
        switch self {
        case .oversized(let actual, let bound):
            return "the file is \(actual) bytes; the bound is \(bound)"
        case .noBlock:
            return "the bytes hold no managed block"
        case .block(let error):
            return error.description
        }
    }
}

/// The input contract for finished bytes: exactly one well-formed block of a
/// supported version, inside a size bound.
public enum PlannedBytes {
    /// 16 MiB. The live file is usually a few hundred bytes, and a block of a few
    /// hundred thousand short entries fits well inside this; the bound exists so
    /// a client cannot make the daemon write an arbitrarily large file.
    public static let sizeBound = 16 << 20

    /// Returns the located block, or throws the reason the bytes are refused.
    public static func validate(_ bytes: Data) throws -> ManagedBlockLocation {
        guard bytes.count <= sizeBound else {
            throw ByteRefusal.oversized(actual: bytes.count, bound: sizeBound)
        }
        let location: ManagedBlockLocation
        do {
            guard let found = try ManagedBlock.locate(in: bytes) else { throw ByteRefusal.noBlock }
            location = found
        } catch let error as BlockError {
            throw ByteRefusal.block(error)
        }
        guard location.version == ManagedBlock.version else {
            throw ByteRefusal.block(.unsupportedVersion(found: location.version, expected: ManagedBlock.version))
        }
        return location
    }

    /// The reason `bytes` would be refused, or `nil` when they are acceptable.
    public static func refusal(_ bytes: Data) -> ByteRefusal? {
        do {
            _ = try validate(bytes)
            return nil
        } catch let refusal as ByteRefusal {
            return refusal
        } catch {
            return .block(.invalidBlock("\(error)"))
        }
    }
}
