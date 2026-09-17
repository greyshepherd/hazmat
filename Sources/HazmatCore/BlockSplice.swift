import Foundation

/// Splices a rendered block into a hosts file, and removes it again.
///
/// Insertion is at the end of the file behind exactly one `\n` separator, so the
/// block always starts a line, and the separator is removed with the block.
/// Replacing an existing block touches the block's own bytes only. Every other
/// byte is carried across untouched.
public enum BlockSplice {
    public static func splice(block: Data, into file: Data) throws -> Data {
        guard let location = try ManagedBlock.locate(in: block) else {
            throw BlockError.invalidBlock("it holds no managed block")
        }
        guard location.range.lowerBound == block.startIndex, location.range.upperBound == block.endIndex else {
            throw BlockError.invalidBlock("it carries content outside its markers")
        }
        guard location.version == ManagedBlock.version else {
            throw BlockError.unsupportedVersion(found: location.version, expected: ManagedBlock.version)
        }

        if let existing = try ManagedBlock.locate(in: file) {
            guard existing.version == ManagedBlock.version else {
                throw BlockError.unsupportedVersion(found: existing.version, expected: ManagedBlock.version)
            }
            return file[file.startIndex..<existing.range.lowerBound] + block + file[existing.range.upperBound...]
        }
        return file + Data([0x0A]) + block
    }

    /// Removes the block, restoring the bytes a splice displaced. A file with no
    /// block is returned unchanged.
    public static func strip(from file: Data) throws -> Data {
        guard let location = try ManagedBlock.locate(in: file) else { return file }

        var start = location.range.lowerBound
        if start > file.startIndex, file[file.index(before: start)] == 0x0A {
            start = file.index(before: start)
        }
        return file[file.startIndex..<start] + file[location.range.upperBound...]
    }
}
