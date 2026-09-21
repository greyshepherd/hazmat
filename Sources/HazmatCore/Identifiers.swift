/// The name a profile uses to refer to a fragment.
public struct FragmentID: Hashable, Comparable, CustomStringConvertible, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    /// `true` when the name starts with a letter or digit, holds only letters,
    /// digits, spaces, `.`, `_` and `-`, ends with neither a space nor `..`, so
    /// it cannot leave its directory.
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

    /// `true` when the name starts with a letter or digit, holds only letters,
    /// digits, spaces, `.`, `_` and `-`, ends with neither a space nor `..`, so
    /// it cannot leave its directory.
    public var isValid: Bool { NameSyntax.isIdentifier(rawValue) }

    public static func < (left: ProfileID, right: ProfileID) -> Bool {
        left.rawValue < right.rawValue
    }
}

/// The grammar a profile or fragment name follows. A name is the file it is
/// stored as and the line a profile names it on, so it may hold a space the way
/// a filename may, but never a path separator, `..`, leading or trailing space,
/// or a leading `.` or `-`.
public enum NameSyntax {
    /// The grammar in one sentence, shown as standing help where a name is
    /// asked for, so the window says the rule before anything is typed.
    public static let requirement =
        "A name starts with a letter or a digit and holds only letters, digits, spaces, '.', '_' and "
        + "'-'; it never ends with a space and never holds '..'."

    /// The allowed characters, as the second half of a refusal.
    private static let allowedCharacters = "Letters, digits, spaces, '.', '_' and '-' are allowed."

    /// Why `text` is not a usable name, or `nil` when it is: one sentence about
    /// *this* name rather than the whole grammar, so a field can say what to
    /// change. `refusal(_:) == nil` exactly when `isIdentifier(_:)` is `true`.
    public static func refusal(_ text: String) -> String? {
        withBytes(of: text) { refusal($0) }
    }

    static func refusal(_ bytes: UnsafeRawBufferPointer) -> String? {
        guard let first = bytes.first else { return "Enter a name." }
        guard ASCII.isLetter(first) || ASCII.isDigit(first) else {
            // A byte above ASCII belongs to a character the grammar does not
            // carry, so the character set is what to say, not where the name
            // starts: "éclair" does start with a letter, just not this one.
            guard first < 0x80 else { return refusing(first) }
            return "A name has to start with a letter or a digit."
        }
        if let offender = bytes.first(where: { !isIdentifierByte($0) }) {
            return refusing(offender)
        }
        guard bytes.last != ASCII.space else { return "A name cannot end with a space." }
        guard !Lines.contains(bytes, "..") else { return "A name cannot hold '..'." }
        return nil
    }

    /// A character the grammar does not allow, named when it can be written in a
    /// sentence. A control byte, or one of a multi-byte character, gets the rule
    /// without being quoted: half a character or a newline would break the line
    /// the sentence stands on.
    private static func refusing(_ byte: UInt8) -> String {
        guard (0x21...0x7E).contains(byte) else {
            return "A name cannot hold that character. \(allowedCharacters)"
        }
        return "A name cannot hold '\(Character(UnicodeScalar(byte)))'. \(allowedCharacters)"
    }

    /// `true` when `text` starts with a letter or a digit, holds only letters,
    /// digits, spaces, `.`, `_` and `-`, ends with neither a space nor `..`, so
    /// it cannot leave its directory and a profile line can carry it.
    public static func isIdentifier(_ text: String) -> Bool {
        withBytes(of: text) { isIdentifier($0) }
    }

    static func isIdentifier(_ bytes: UnsafeRawBufferPointer) -> Bool {
        guard let first = bytes.first, ASCII.isLetter(first) || ASCII.isDigit(first) else { return false }
        guard bytes.allSatisfy(isIdentifierByte) else { return false }
        guard bytes.last != ASCII.space else { return false }
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

    /// A hostname holds no space; a name a profile or fragment is stored under
    /// may, so the two grammars share every character but that one.
    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        isNameCharacter(byte) || byte == ASCII.space
    }
}
