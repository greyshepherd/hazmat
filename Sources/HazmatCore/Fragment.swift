import Foundation

/// Where a line came from: the fragment, and its one-based line number.
public struct SourceLocation: Hashable, Sendable {
    public let fragment: FragmentID
    public let line: Int

    public init(fragment: FragmentID, line: Int) {
        self.fragment = fragment
        self.line = line
    }
}

/// A host entry: one address, a primary host name, and any aliases.
public struct HostEntry: Equatable, Sendable {
    public let address: String
    public let family: AddressFamily
    /// Primary host name first, then aliases in the order written.
    public let names: [String]
    public let source: SourceLocation

    init(address: String, family: AddressFamily, names: [String], source: SourceLocation) {
        self.address = address
        self.family = family
        self.names = names
        self.source = source
    }

    public var primaryName: String { names[0] }

    public var aliases: [String] { Array(names.dropFirst()) }
}

/// A directive that strikes `name` from the layers below it. Written as a
/// comment so a fragment stays a valid hosts file for other editors.
public struct Removal: Equatable, Sendable {
    public let name: String
    public let source: SourceLocation

    public init(name: String, source: SourceLocation) {
        self.name = name
        self.source = source
    }
}

public enum FragmentItem: Equatable, Sendable {
    case entry(HostEntry)
    case removal(Removal)
}

/// A fragment's content, with entries and removals in file order.
public struct ParsedFragment: Equatable, Sendable {
    public let id: FragmentID
    public let items: [FragmentItem]

    public init(id: FragmentID, items: [FragmentItem]) {
        self.id = id
        self.items = items
    }

    public var entries: [HostEntry] {
        items.compactMap { item in
            switch item {
            case .entry(let entry): return entry
            case .removal: return nil
            }
        }
    }

    public var removals: [Removal] {
        items.compactMap { item in
            switch item {
            case .entry: return nil
            case .removal(let removal): return removal
            }
        }
    }
}

/// Reads the hosts grammar, reporting malformed lines instead of guessing at
/// them. A malformed line contributes no entry.
public enum FragmentParser {
    public struct Outcome: Equatable, Sendable {
        public let fragment: ParsedFragment
        /// Every malformed line, in file order.
        public let problems: [CompositionProblem]

        public init(fragment: ParsedFragment, problems: [CompositionProblem]) {
            self.fragment = fragment
            self.problems = problems
        }

        /// Whether the text carries a `hazmat:` directive, well formed or not.
        /// Asked of the parser rather than matched against the text, so the rule
        /// a fetch enforces is the rule the grammar reads.
        public var carriesDirective: Bool {
            if !fragment.removals.isEmpty { return true }
            return problems.contains { problem in
                guard case .malformedEntry(_, _, _, let detail) = problem else { return false }
                switch detail {
                case .unknownDirective, .malformedRemovalDirective: return true
                case .missingName, .invalidAddress, .invalidHostName, .duplicateHostName: return false
                }
            }
        }
    }

    public static func parse(_ text: String, as id: FragmentID) -> Outcome {
        withBytes(of: text) { parse($0, as: id) }
    }

    /// Reads bytes that are already in hand, so a store's file is never decoded
    /// into a `String` only to be parsed.
    public static func parse(_ bytes: Data, as id: FragmentID) -> Outcome {
        bytes.withUnsafeBytes { parse($0, as: id) }
    }

    static func parse(_ bytes: UnsafeRawBufferPointer, as id: FragmentID) -> Outcome {
        var items: [FragmentItem] = []
        var problems: [CompositionProblem] = []

        for (index, range) in Lines.contents(of: bytes).enumerated() {
            let lineNumber = index + 1
            let line = UnsafeRawBufferPointer(rebasing: bytes[range])
            if let problem = parse(line, as: id, lineNumber: lineNumber, into: &items) {
                problems.append(problem)
            }
        }
        return Outcome(fragment: ParsedFragment(id: id, items: items), problems: problems)
    }

    private static func parse(
        _ line: UnsafeRawBufferPointer,
        as id: FragmentID,
        lineNumber: Int,
        into items: inout [FragmentItem]
    ) -> CompositionProblem? {
        let source = SourceLocation(fragment: id, line: lineNumber)
        let trimmed = Lines.trimmed(line)
        guard !trimmed.isEmpty else { return nil }

        if trimmed[0] == ASCII.hash {
            return parseComment(trimmed, source: source, into: &items)
        }

        let content = Lines.trimmed(Lines.beforeComment(trimmed))
        guard !content.isEmpty else { return nil }

        let fields = Lines.fields(of: content)
        guard let family = AddressSyntax.family(of: fields[0]) else {
            let address = Lines.text(of: fields[0])
            return .malformedEntry(fragment: id, line: lineNumber, text: Lines.text(of: line), detail: .invalidAddress(address))
        }
        guard fields.count > 1 else {
            return .malformedEntry(fragment: id, line: lineNumber, text: Lines.text(of: line), detail: .missingName)
        }

        var names: [String] = []
        for field in fields.dropFirst() {
            guard NameSyntax.isHostName(field) else {
                return .malformedEntry(fragment: id, line: lineNumber, text: Lines.text(of: line), detail: .invalidHostName(Lines.text(of: field)))
            }
            let name = Lines.text(of: field)
            guard !names.contains(name) else {
                return .malformedEntry(fragment: id, line: lineNumber, text: Lines.text(of: line), detail: .duplicateHostName(name))
            }
            names.append(name)
        }
        items.append(.entry(HostEntry(address: Lines.text(of: fields[0]), family: family, names: names, source: source)))
        return nil
    }

    private static func parseComment(
        _ trimmed: UnsafeRawBufferPointer,
        source: SourceLocation,
        into items: inout [FragmentItem]
    ) -> CompositionProblem? {
        let comment = Lines.trimmed(UnsafeRawBufferPointer(rebasing: trimmed.dropFirst()))
        let fields = Lines.fields(of: comment)
        guard let directive = fields.first, Lines.hasPrefix(directive, "hazmat:") else { return nil }

        let directiveText = Lines.text(of: directive)
        guard directiveText == "hazmat:remove", fields.count == 2 else {
            let text = Lines.text(of: trimmed)
            guard directiveText == "hazmat:remove" else {
                return .malformedEntry(fragment: source.fragment, line: source.line, text: text, detail: .unknownDirective(directiveText))
            }
            return .malformedEntry(fragment: source.fragment, line: source.line, text: text, detail: .malformedRemovalDirective(text))
        }

        guard NameSyntax.isHostName(fields[1]) else {
            return .malformedEntry(fragment: source.fragment, line: source.line, text: Lines.text(of: trimmed), detail: .invalidHostName(Lines.text(of: fields[1])))
        }
        items.append(.removal(Removal(name: Lines.text(of: fields[1]), source: source)))
        return nil
    }
}

/// The bytes the hosts and profile grammars are written in terms of.
enum ASCII {
    static let tab: UInt8 = 0x09
    static let lineFeed: UInt8 = 0x0A
    static let carriageReturn: UInt8 = 0x0D
    static let space: UInt8 = 0x20
    static let hash: UInt8 = 0x23
    static let percent: UInt8 = 0x25
    static let dash: UInt8 = 0x2D
    static let dot: UInt8 = 0x2E
    static let zero: UInt8 = 0x30
    static let colon: UInt8 = 0x3A
    static let underscore: UInt8 = 0x5F

    static func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }

    static func isLetter(_ byte: UInt8) -> Bool {
        (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }
}

/// Runs `body` over the text's UTF-8 bytes, without copying them when the string
/// already holds them contiguously.
func withBytes<T>(of text: String, _ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
    if let value = try text.utf8.withContiguousStorageIfAvailable({ try body(UnsafeRawBufferPointer($0)) }) {
        return value
    }
    return try Array(text.utf8).withUnsafeBytes(body)
}

enum Lines {
    /// The byte range of every line's content in `bytes`: lines are split at
    /// `0x0A`, one trailing `0x0D` is dropped from each, and a final line that
    /// carries no terminator is still a line.
    static func contents(of bytes: UnsafeRawBufferPointer) -> [Range<Int>] {
        guard !bytes.isEmpty else { return [] }
        var ranges: [Range<Int>] = []
        var lineStart = 0
        while lineStart < bytes.count {
            var cursor = lineStart
            while cursor < bytes.count, bytes[cursor] != ASCII.lineFeed { cursor += 1 }
            var contentEnd = cursor
            if contentEnd > lineStart, bytes[contentEnd - 1] == ASCII.carriageReturn { contentEnd -= 1 }
            ranges.append(lineStart..<contentEnd)
            lineStart = cursor < bytes.count ? cursor + 1 : cursor
        }
        return ranges
    }

    /// `bytes` without leading or trailing spaces, tabs and carriage returns.
    static func trimmed(_ bytes: UnsafeRawBufferPointer) -> UnsafeRawBufferPointer {
        var start = 0
        var end = bytes.count
        while start < end, isTrimmed(bytes[start]) { start += 1 }
        while end > start, isTrimmed(bytes[end - 1]) { end -= 1 }
        return UnsafeRawBufferPointer(rebasing: bytes[start..<end])
    }

    /// `bytes` up to the first `#`, which begins an inline comment.
    static func beforeComment(_ bytes: UnsafeRawBufferPointer) -> UnsafeRawBufferPointer {
        guard let index = bytes.firstIndex(of: ASCII.hash) else { return bytes }
        return UnsafeRawBufferPointer(rebasing: bytes[..<index])
    }

    /// A line's fields: runs of bytes separated by spaces and tabs. A run of
    /// separators contributes nothing, the way `split` reads them.
    static func fields(of bytes: UnsafeRawBufferPointer) -> [UnsafeRawBufferPointer] {
        var fields: [UnsafeRawBufferPointer] = []
        var index = 0
        while index < bytes.count {
            while index < bytes.count, isSeparator(bytes[index]) { index += 1 }
            guard index < bytes.count else { break }
            let start = index
            while index < bytes.count, !isSeparator(bytes[index]) { index += 1 }
            fields.append(UnsafeRawBufferPointer(rebasing: bytes[start..<index]))
        }
        return fields
    }

    /// Whether `bytes` starts with `prefix`.
    static func hasPrefix(_ bytes: UnsafeRawBufferPointer, _ prefix: String) -> Bool {
        var index = 0
        for byte in prefix.utf8 {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
        }
        return true
    }

    /// Whether `pattern` occurs anywhere in `bytes`.
    static func contains(_ bytes: UnsafeRawBufferPointer, _ pattern: String) -> Bool {
        let pattern = Array(pattern.utf8)
        guard !pattern.isEmpty, pattern.count <= bytes.count else { return false }
        for start in 0...(bytes.count - pattern.count) where matches(bytes, at: start, pattern) {
            return true
        }
        return false
    }

    /// `bytes` split at every occurrence of `separator`, keeping the empty pieces
    /// between and around them, the way `components(separatedBy:)` reads them.
    static func components(of bytes: UnsafeRawBufferPointer, separatedBy separator: String) -> [UnsafeRawBufferPointer] {
        let pattern = Array(separator.utf8)
        var pieces: [UnsafeRawBufferPointer] = []
        var start = 0
        var index = 0
        while index + pattern.count <= bytes.count {
            if matches(bytes, at: index, pattern) {
                pieces.append(UnsafeRawBufferPointer(rebasing: bytes[start..<index]))
                index += pattern.count
                start = index
            } else {
                index += 1
            }
        }
        pieces.append(UnsafeRawBufferPointer(rebasing: bytes[start..<bytes.count]))
        return pieces
    }

    private static func matches(_ bytes: UnsafeRawBufferPointer, at index: Int, _ pattern: [UInt8]) -> Bool {
        var offset = 0
        while offset < pattern.count {
            if bytes[index + offset] != pattern[offset] { return false }
            offset += 1
        }
        return true
    }

    /// A line's bytes as text, decoded only when a problem has to name them.
    static func text(of bytes: UnsafeRawBufferPointer) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    /// The character-level trim a profile rewrite needs, because it keeps the
    /// slice's own indices to replace the name where it stands.
    static func trimmed(_ slice: Substring) -> Substring {
        var result = slice
        while let first = result.first, first == " " || first == "\t" || first == "\r" {
            result = result.dropFirst()
        }
        while let last = result.last, last == " " || last == "\t" || last == "\r" {
            result = result.dropLast()
        }
        return result
    }

    private static func isTrimmed(_ byte: UInt8) -> Bool {
        byte == ASCII.space || byte == ASCII.tab || byte == ASCII.carriageReturn
    }

    private static func isSeparator(_ byte: UInt8) -> Bool {
        byte == ASCII.space || byte == ASCII.tab
    }
}
