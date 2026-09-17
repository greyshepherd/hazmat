import Foundation

/// Renders a composition into the bytes of a managed block.
public enum BlockRenderer {
    /// The block uses `\n` line endings and ends with one. Names come out in
    /// resolution order, grouped on one line when a single entry supplied them.
    public static func render(_ composition: Composition) -> Data {
        var lines = [ManagedBlock.startMarker()]
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
            lines.append("\(first.address) \(names.joined(separator: " "))")
            index = next
        }
        lines.append(ManagedBlock.endMarker())
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}
