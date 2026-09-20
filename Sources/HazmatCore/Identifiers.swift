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
        withBytes(of: text) { isIdentifier($0) }
    }

    /// `true` when the name starts with a letter or digit, contains only
    /// `A-Z a-z 0-9 . _ -`, and holds no `..`, so it cannot leave its directory.
    static func isIdentifier(_ bytes: UnsafeRawBufferPointer) -> Bool {
        guard let first = bytes.first, ASCII.isLetter(first) || ASCII.isDigit(first) else { return false }
        guard bytes.allSatisfy(isNameCharacter) else { return false }
        return !Lines.contains(bytes, "..")
    }

    static func isHostName(_ text: String) -> Bool {
        withBytes(of: text) { isHostName($0) }
    }

    static func isHostName(_ bytes: UnsafeRawBufferPointer) -> Bool {
        !bytes.isEmpty && bytes.allSatisfy(isNameCharacter)
    }

    private static func isNameCharacter(_ byte: UInt8) -> Bool {
        ASCII.isLetter(byte) || ASCII.isDigit(byte)
            || byte == ASCII.dot || byte == ASCII.underscore || byte == ASCII.dash
    }
}
