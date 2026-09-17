/// Every problem found while reading a fragment or a profile, reported in full
/// rather than one at a time.
public enum CompositionProblem: Equatable, Sendable {
    case missingProfile(ProfileID)
    /// A profile names a fragment the store does not hold.
    case missingFragment(profile: ProfileID, line: Int, fragment: FragmentID)
    /// A fragment line is not a valid host entry.
    case malformedEntry(fragment: FragmentID, line: Int, text: String, detail: MalformedEntryDetail)
    /// A profile line is not a valid fragment reference.
    case malformedReference(profile: ProfileID, line: Int, text: String)

    public var message: String {
        switch self {
        case .missingProfile(let profile):
            return "profile '\(profile)' is not in the store"
        case .missingFragment(let profile, let line, let fragment):
            return "profile '\(profile)' line \(line): fragment '\(fragment)' is not in the store"
        case .malformedEntry(let fragment, let line, _, let detail):
            return "fragment '\(fragment)' line \(line): \(detail.message)"
        case .malformedReference(let profile, let line, let text):
            return "profile '\(profile)' line \(line): '\(text)' is not a fragment reference"
        }
    }
}

public enum MalformedEntryDetail: Equatable, Sendable {
    case missingName
    case invalidAddress(String)
    case invalidHostName(String)
    case duplicateHostName(String)
    /// A `hazmat:` directive this version does not define.
    case unknownDirective(String)
    case malformedRemovalDirective(String)

    public var message: String {
        switch self {
        case .missingName:
            return "the line has an address but no host name"
        case .invalidAddress(let address):
            return "'\(address)' is not a valid address"
        case .invalidHostName(let name):
            return "'\(name)' is not a valid host name"
        case .duplicateHostName(let name):
            return "'\(name)' appears twice on the line"
        case .unknownDirective(let directive):
            return "'\(directive)' is not a directive this version knows"
        case .malformedRemovalDirective(let text):
            return "'\(text)' is not a valid removal directive"
        }
    }
}

/// Composition refused. `problems` holds every problem found in the same pass;
/// nothing was applied.
public struct CompositionError: Error, Equatable, Sendable, CustomStringConvertible {
    public let problems: [CompositionProblem]

    public init(_ problems: [CompositionProblem]) {
        self.problems = problems
    }

    public var description: String {
        problems.map(\.message).joined(separator: "\n")
    }
}
