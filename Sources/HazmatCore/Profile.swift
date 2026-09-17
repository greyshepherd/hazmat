/// An ordered stack of fragment references. Reading order is stack order.
public struct Profile: Equatable, Sendable {
    public let id: ProfileID
    public let references: [ProfileReference]

    public init(id: ProfileID, references: [ProfileReference]) {
        self.id = id
        self.references = references
    }
}

public struct ProfileReference: Equatable, Sendable {
    public let fragment: FragmentID
    /// One-based line number the reference was written on.
    public let line: Int

    public init(fragment: FragmentID, line: Int) {
        self.fragment = fragment
        self.line = line
    }
}

/// The text a profile is written as: one fragment reference per line.
public enum ProfileText {
    public static func render(_ layers: [FragmentID]) -> String {
        layers.map { "\($0.rawValue)\n" }.joined()
    }
}

/// Reads a profile: one fragment reference per line, comments and blank lines
/// permitted, order preserved.
public enum ProfileParser {
    public struct Outcome: Equatable, Sendable {
        public let profile: Profile
        public let problems: [CompositionProblem]

        public init(profile: Profile, problems: [CompositionProblem]) {
            self.profile = profile
            self.problems = problems
        }
    }

    public static func parse(_ text: String, as id: ProfileID) -> Outcome {
        var references: [ProfileReference] = []
        var problems: [CompositionProblem] = []

        for (index, line) in Lines.of(text).enumerated() {
            let lineNumber = index + 1
            let trimmed = Lines.trimmed(line)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let content = Lines.trimmed(trimmed.prefix(while: { $0 != "#" }))
            guard !content.isEmpty else { continue }

            let fragmentID = FragmentID(String(content))
            guard fragmentID.isValid else {
                problems.append(.malformedReference(profile: id, line: lineNumber, text: String(content)))
                continue
            }
            references.append(ProfileReference(fragment: fragmentID, line: lineNumber))
        }
        return Outcome(profile: Profile(id: id, references: references), problems: problems)
    }
}
