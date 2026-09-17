/// Where a first apply lands the block relative to the entries already in the
/// file. An existing block is replaced where it is, so position only governs
/// insertion.
public enum BlockPosition: String, CaseIterable, Equatable, Sendable {
    /// Immediately before the first entry line, so the resolver meets Hazmat's
    /// entries before entries written by other tools.
    case beforeFirstEntry
    /// At the end of the file, so entries written by other tools come first.
    case endOfFile

    /// The position an apply uses when the caller names none.
    ///
    /// The resolver measurement recorded in design.md is inconclusive: this
    /// machine's resolver answers a duplicated name with both addresses, so
    /// neither position is safer by measurement. The default is therefore
    /// unmeasured, and it stays where the splice put the block before the choice
    /// existed: the end of the file, behind the entries other tools own.
    public static let `default`: BlockPosition = .endOfFile
}
