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

    /// The block uses `\n` line endings and ends with one. Names come out in
    /// resolution order, grouped on one line when a single entry supplied them.
    public static func render(_ composition: Composition) -> Data {
        var lines = [ManagedBlock.startMarker()]
        lines.append(contentsOf: entries(composition).map { entry in
            "\(entry.address) \(entry.names.joined(separator: " "))"
        })
        lines.append(ManagedBlock.endMarker())
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}
