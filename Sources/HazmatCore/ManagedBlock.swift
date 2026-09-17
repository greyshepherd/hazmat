import Foundation

/// The managed block grammar: the markers that delimit the region Hazmat owns
/// inside a hosts file.
public enum ManagedBlock {
    /// The format version every marker written by this code carries. A block
    /// written with another version is read and reported, never rewritten.
    public static let version = 1

    /// Reserved token. A line holding it must be a well-formed marker; anything
    /// else is refused rather than ignored, so a damaged marker cannot pass as
    /// ordinary content.
    public static let token = "hazmat:managed"

    public static func startMarker(version: Int) -> String {
        "# >>> \(token) v\(version) >>>"
    }

    public static func endMarker(version: Int) -> String {
        "# <<< \(token) v\(version) <<<"
    }

    public static func startMarker() -> String { startMarker(version: version) }

    public static func endMarker() -> String { endMarker(version: version) }

    /// Finds the managed block in `file`, or returns `nil` when the file holds
    /// none. Reading reports a foreign version; refusing it is the splice's job.
    public static func locate(in file: Data) throws -> ManagedBlockLocation? {
        var completed: ManagedBlockLocation?
        var pending: (line: Int, version: Int, range: Range<Int>)?

        var lineNumber = 1
        var lineStart = file.startIndex
        while lineStart < file.endIndex {
            var cursor = lineStart
            while cursor < file.endIndex, file[cursor] != 0x0A { cursor += 1 }
            let lineEnd = cursor < file.endIndex ? cursor + 1 : cursor
            var contentEnd = cursor
            if contentEnd > lineStart, file[contentEnd - 1] == 0x0D { contentEnd -= 1 }
            let line = String(decoding: file[lineStart..<contentEnd], as: UTF8.self)
            let fullRange = lineStart..<lineEnd

            switch markerShape(of: line) {
            case .none:
                break
            case .malformed:
                throw BlockError.malformedMarker(line: lineNumber, text: line)
            case .start(let version):
                if let open = pending {
                    throw BlockError.multipleBlocks(firstLine: open.line, secondLine: lineNumber)
                }
                if let already = completed {
                    throw BlockError.multipleBlocks(firstLine: already.startLine, secondLine: lineNumber)
                }
                pending = (lineNumber, version, fullRange)
            case .end(let version):
                guard let open = pending else {
                    throw BlockError.endMarkerWithoutStart(line: lineNumber)
                }
                guard open.version == version else {
                    throw BlockError.mismatchedVersions(startVersion: open.version, endVersion: version, line: lineNumber)
                }
                completed = ManagedBlockLocation(
                    version: version,
                    startLine: open.line,
                    range: open.range.lowerBound..<fullRange.upperBound
                )
                pending = nil
            }

            lineNumber += 1
            lineStart = lineEnd
        }

        if let open = pending {
            throw BlockError.unterminatedBlock(line: open.line)
        }
        return completed
    }

    enum MarkerShape {
        case none
        case start(Int)
        case end(Int)
        case malformed
    }

    static func markerShape(of line: String) -> MarkerShape {
        guard line.contains(token) else { return .none }
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count == 5,
              fields[0] == "#",
              fields[2] == token,
              fields[4] == fields[1],
              let version = versionNumber(fields[3])
        else { return .malformed }

        switch fields[1] {
        case ">>>": return .start(version)
        case "<<<": return .end(version)
        default: return .malformed
        }
    }

    private static func versionNumber(_ field: Substring) -> Int? {
        guard field.hasPrefix("v") else { return nil }
        let digits = field.dropFirst()
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }
}

public struct ManagedBlockLocation: Equatable, Sendable {
    /// The version recorded in the markers.
    public let version: Int
    /// One-based line number of the start marker.
    public let startLine: Int
    /// The block: the start marker's first byte through the end marker's line
    /// terminator, or through the end of the file when it carries none.
    public let range: Range<Int>
}

public enum BlockError: Error, Equatable, Sendable, CustomStringConvertible {
    case malformedMarker(line: Int, text: String)
    case unterminatedBlock(line: Int)
    case endMarkerWithoutStart(line: Int)
    case multipleBlocks(firstLine: Int, secondLine: Int)
    case mismatchedVersions(startVersion: Int, endVersion: Int, line: Int)
    case unsupportedVersion(found: Int, expected: Int)
    /// The value handed to the splice is not one whole block of this version.
    case invalidBlock(String)

    public var description: String {
        switch self {
        case .malformedMarker(let line, let text):
            return "line \(line) uses the reserved marker token but is not a marker: '\(text)'"
        case .unterminatedBlock(let line):
            return "the block opened on line \(line) has no end marker"
        case .endMarkerWithoutStart(let line):
            return "line \(line) holds an end marker with no start marker"
        case .multipleBlocks(let first, let second):
            return "the file holds more than one block: line \(first) and line \(second)"
        case .mismatchedVersions(let start, let end, let line):
            return "line \(line) ends a version \(start) block with a version \(end) marker"
        case .unsupportedVersion(let found, let expected):
            return "the block is version \(found); this version writes and splices version \(expected)"
        case .invalidBlock(let reason):
            return "the block is not usable: \(reason)"
        }
    }
}
