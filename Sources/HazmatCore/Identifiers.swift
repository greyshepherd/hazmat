/// The name a profile uses to refer to a fragment.
public struct FragmentID: Hashable, Comparable, CustomStringConvertible, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    /// `true` when the name starts with a letter or digit, contains only
    /// `A-Z a-z 0-9 . _ -`, and holds no `..`, so it cannot leave its directory.
    public var isValid: Bool { NameSyntax.isIdentifier(rawValue) }

    public static func < (left: FragmentID, right: FragmentID) -> Bool {
        left.rawValue < right.rawValue
    }
}

/// The name of a profile.
public struct ProfileID: Hashable, Comparable, CustomStringConvertible, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    /// `true` when the name starts with a letter or digit, contains only
    /// `A-Z a-z 0-9 . _ -`, and holds no `..`, so it cannot leave its directory.
    public var isValid: Bool { NameSyntax.isIdentifier(rawValue) }

    public static func < (left: ProfileID, right: ProfileID) -> Bool {
        left.rawValue < right.rawValue
    }
}

enum NameSyntax {
    static func isIdentifier(_ text: String) -> Bool {
        guard let first = text.first, first.isASCII, first.isLetter || first.isNumber else { return false }
        return text.allSatisfy(isNameCharacter) && !text.contains("..")
    }

    static func isHostName(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(isNameCharacter)
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber
            || character == "." || character == "_" || character == "-"
    }
}
