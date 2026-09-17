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
    }

    public static func parse(_ text: String, as id: FragmentID) -> Outcome {
        var items: [FragmentItem] = []
        var problems: [CompositionProblem] = []

        for (index, line) in Lines.of(text).enumerated() {
            let lineNumber = index + 1
            if let problem = parse(line, as: id, lineNumber: lineNumber, into: &items) {
                problems.append(problem)
            }
        }
        return Outcome(fragment: ParsedFragment(id: id, items: items), problems: problems)
    }

    private static func parse(
        _ line: String,
        as id: FragmentID,
        lineNumber: Int,
        into items: inout [FragmentItem]
    ) -> CompositionProblem? {
        let source = SourceLocation(fragment: id, line: lineNumber)
        let trimmed = Lines.trimmed(line)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("#") {
            return parseComment(trimmed, source: source, into: &items)
        }

        let content = Lines.trimmed(trimmed.prefix(while: { $0 != "#" }))
        guard !content.isEmpty else { return nil }

        let fields = content.split(whereSeparator: { $0 == " " || $0 == "\t" })
        let address = String(fields[0])
        guard let family = AddressSyntax.family(of: address) else {
            return .malformedEntry(fragment: id, line: lineNumber, text: line, detail: .invalidAddress(address))
        }
        guard fields.count > 1 else {
            return .malformedEntry(fragment: id, line: lineNumber, text: line, detail: .missingName)
        }

        var names: [String] = []
        for field in fields.dropFirst() {
            let name = String(field)
            guard NameSyntax.isHostName(name) else {
                return .malformedEntry(fragment: id, line: lineNumber, text: line, detail: .invalidHostName(name))
            }
            guard !names.contains(name) else {
                return .malformedEntry(fragment: id, line: lineNumber, text: line, detail: .duplicateHostName(name))
            }
            names.append(name)
        }
        items.append(.entry(HostEntry(address: address, family: family, names: names, source: source)))
        return nil
    }

    private static func parseComment(
        _ trimmed: Substring,
        source: SourceLocation,
        into items: inout [FragmentItem]
    ) -> CompositionProblem? {
        let comment = Lines.trimmed(trimmed.dropFirst())
        let fields = comment.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let directive = fields.first, directive.hasPrefix("hazmat:") else { return nil }

        guard directive == "hazmat:remove", fields.count == 2 else {
            let text = String(trimmed)
            guard directive == "hazmat:remove" else {
                return .malformedEntry(fragment: source.fragment, line: source.line, text: text, detail: .unknownDirective(String(directive)))
            }
            return .malformedEntry(fragment: source.fragment, line: source.line, text: text, detail: .malformedRemovalDirective(text))
        }

        let name = String(fields[1])
        guard NameSyntax.isHostName(name) else {
            return .malformedEntry(fragment: source.fragment, line: source.line, text: String(trimmed), detail: .invalidHostName(name))
        }
        items.append(.removal(Removal(name: name, source: source)))
        return nil
    }
}

enum Lines {
    /// Splits text into lines, dropping a single trailing carriage return from
    /// each, and keeping a final line that carries no terminator.
    static func of(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n") {
            lines.removeLast()
        }
        return lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }

    static func trimmed(_ text: String) -> Substring {
        trimmed(text[...])
    }

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
}
