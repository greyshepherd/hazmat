import Foundation

/// One line of a rendered block: an address, the names it carries, and where
/// they came from. The block's entry lines are these values in order, so a
/// reader that counts or lists entries counts the lines the renderer writes.
public struct BlockEntry: Equatable, Sendable {
    public let address: String
    public let family: AddressFamily
    public let names: [String]
    public let source: SourceLocation

    public init(address: String, family: AddressFamily, names: [String], source: SourceLocation) {
        self.address = address
        self.family = family
        self.names = names
        self.source = source
    }
}

/// Renders a composition into the bytes of a managed block.
public enum BlockRenderer {
    /// The composition's entries in resolution order, grouped the way the
    /// renderer groups them: names supplied by one entry on one line.
    public static func entries(_ composition: Composition) -> [BlockEntry] {
        var entries: [BlockEntry] = []
        var index = 0
        while index < composition.resolved.count {
            let first = composition.resolved[index]
            var names = [first.name]
            var next = index + 1
            while next < composition.resolved.count,
                  composition.resolved[next].source == first.source,
                  composition.resolved[next].family == first.family {
                names.append(composition.resolved[next].name)
                next += 1
            }
            entries.append(
                BlockEntry(
                    address: first.address,
                    family: first.family,
                    names: names,
                    source: first.source
                )
            )
            index = next
        }
        return entries
    }

    /// How many lines `entries` would hold, counted without building them: the
    /// count is shown on every look at the block, the lines only in its table.
    public static func entryCount(_ composition: Composition) -> Int {
        var count = 0
        var index = 0
        while index < composition.resolved.count {
            let first = composition.resolved[index]
            var next = index + 1
            while next < composition.resolved.count,
                  composition.resolved[next].source == first.source,
                  composition.resolved[next].family == first.family {
                next += 1
            }
            count += 1
            index = next
        }
        return count
    }

    /// How many entry lines a rendered block holds: its lines less the two
    /// markers. Counted from the bytes, so a reader holding the block and not
    /// the composition it came from still has the number.
    public static func entryCount(in rendered: Data) -> Int {
        var lines = 0
        rendered.withUnsafeBytes { bytes in
            for byte in bytes where byte == ASCII.lineFeed { lines += 1 }
        }
        return max(lines - 2, 0)
    }

    /// The block uses `\n` line endings and ends with one. Names come out in
    /// resolution order, grouped on one line when a single entry supplied them.
    public static func render(_ composition: Composition) -> Data {
        render(entries: entries(composition))
    }

    /// The same bytes, from entry lines already in hand, so a reader that has
    /// them does not build them a second time. A block of a hundred thousand
    /// lines is written straight to bytes rather than through one string per
    /// line and a join of them all.
    public static func render(entries: [BlockEntry]) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(entries.count * 40)
        append(ManagedBlock.startMarker(), to: &bytes)
        bytes.append(ASCII.lineFeed)
        for entry in entries {
            append(entry.address, to: &bytes)
            for name in entry.names {
                bytes.append(ASCII.space)
                append(name, to: &bytes)
            }
            bytes.append(ASCII.lineFeed)
        }
        append(ManagedBlock.endMarker(), to: &bytes)
        bytes.append(ASCII.lineFeed)
        return Data(bytes)
    }

    private static func append(_ text: String, to bytes: inout [UInt8]) {
        // A native string's UTF-8 is already contiguous, so this appends it in
        // one copy rather than a byte at a time.
        if text.utf8.withContiguousStorageIfAvailable({ bytes.append(contentsOf: $0) }) == nil {
            bytes.append(contentsOf: text.utf8)
        }
    }
}
