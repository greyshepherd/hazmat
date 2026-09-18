import Foundation
import HazmatCore

/// A write the window has asked for and not yet performed. It carries the file
/// and the entry count so the confirmation can name them, and whether the write
/// is destructive, which the window styles and words accordingly.
public enum WriteRequest: Equatable, Sendable {
    case apply(profile: ProfileID, entries: Int, file: String)
    case overwriteDrift(profile: ProfileID, entries: Int, file: String)
    case revert(profile: ProfileID, file: String, removesBlock: Bool)
    case removeBlock(file: String)

    public var title: String {
        switch self {
        case .apply(_, let entries, let file):
            return "Apply \(entries) \(entries == 1 ? "entry" : "entries") to \(file)?"
        case .overwriteDrift(_, let entries, let file):
            return "Replace the block in \(file) with \(entries) \(entries == 1 ? "entry" : "entries")?"
        case .revert(_, let file, let removesBlock):
            return removesBlock ? "Remove the managed block from \(file)?" : "Restore the previous block in \(file)?"
        case .removeBlock(let file):
            return "Remove the managed block from \(file)?"
        }
    }

    public var message: String {
        switch self {
        case .apply:
            return "Hazmat replaces only the block between its markers. Everything outside them stays byte for byte, and the block it replaces is kept so the change can be reverted."
        case .overwriteDrift:
            return "The live block matches no profile in the store, so another tool may have written it. Replacing it discards those bytes; everything outside the markers is left alone."
        case .revert(_, _, let removesBlock):
            return removesBlock
                ? "The apply installed this block into a file that held none, so reverting removes it and leaves the rest of the file as it was."
                : "The block this apply replaced is written back, replacing the block the apply wrote. Everything outside the markers stays byte for byte."
        case .removeBlock:
            return "The block between the Hazmat markers is removed. Everything outside the markers stays byte for byte."
        }
    }

    public var confirmTitle: String {
        switch self {
        case .apply: return "Apply"
        case .overwriteDrift: return "Replace the Block"
        case .revert(_, _, let removesBlock): return removesBlock ? "Remove the Block" : "Restore"
        case .removeBlock: return "Remove the Block"
        }
    }

    /// Overwriting a block no profile owns, and removing the block, discard
    /// bytes the store cannot restore, so the window styles them as destructive.
    public var isDestructive: Bool {
        switch self {
        case .apply, .revert: return false
        case .overwriteDrift, .removeBlock: return true
        }
    }

    public var file: String {
        switch self {
        case .apply(_, _, let file), .overwriteDrift(_, _, let file), .revert(_, let file, _), .removeBlock(let file):
            return file
        }
    }

    public var entryCount: Int? {
        switch self {
        case .apply(_, let entries, _), .overwriteDrift(_, let entries, _):
            return entries
        case .revert, .removeBlock:
            return nil
        }
    }

    public var profile: ProfileID? {
        switch self {
        case .apply(let profile, _, _), .overwriteDrift(let profile, _, _), .revert(let profile, _, _):
            return profile
        case .removeBlock:
            return nil
        }
    }
}
