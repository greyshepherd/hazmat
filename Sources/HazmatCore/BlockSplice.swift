import Foundation

/// Splices a rendered block into a hosts file, and removes it again.
///
/// Insertion is behind exactly one `\n` separator, so the block always starts a
/// line, and the separator is removed with the block. An existing block is
/// replaced where it is: the position choice governs insertion only. Every other
/// byte is carried across untouched.
public enum BlockSplice {
    public static func splice(block: Data, into file: Data, at position: BlockPosition = .endOfFile) throws -> Data {
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

        switch position {
        case .endOfFile:
            return file + Data([0x0A]) + block
        case .beforeFirstEntry:
            let insertion = firstEntryIndex(in: file)
            return file[file.startIndex..<insertion] + Data([0x0A]) + block + file[insertion...]
        }
    }

    /// The index the first entry line starts at: the first line holding
    /// something other than whitespace or a comment. The end of the file when
    /// every line is blank or a comment.
    static func firstEntryIndex(in file: Data) -> Data.Index {
        var lineStart = file.startIndex
        while lineStart < file.endIndex {
            var cursor = lineStart
            while cursor < file.endIndex, file[cursor] != 0x0A { cursor += 1 }
            let lineEnd = cursor < file.endIndex ? cursor + 1 : cursor
            var contentEnd = cursor
            if contentEnd > lineStart, file[contentEnd - 1] == 0x0D { contentEnd -= 1 }

            let line = file[lineStart..<contentEnd]
            let firstContent = line.first { $0 != 0x20 && $0 != 0x09 }
            if let firstContent, firstContent != 0x23 {
                return lineStart
            }
            lineStart = lineEnd
        }
        return file.endIndex
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
