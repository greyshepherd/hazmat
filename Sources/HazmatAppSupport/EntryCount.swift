import Foundation

/// How many entries a fragment or a block holds, as the window says it: one
/// entry, two entries, 14,203 entries.
///
/// One place, so the same number reads the same in the sidebar, the detail pane
/// and a confirmation. The digits are grouped the way the reader's locale groups
/// them, because a fetched blocklist runs to six figures and an unbroken run of
/// them is not a number anyone reads.
public enum EntryCount {
    public static func phrase(_ count: Int) -> String {
        "\(count.formatted()) \(count == 1 ? "entry" : "entries")"
    }
}
