/// The address families a host entry can carry. A name resolving in both is a
/// union, not a conflict.
public enum AddressFamily: String, CaseIterable, Hashable, Sendable {
    case ipv4
    case ipv6
}

/// Address grammar as `/etc/hosts` uses it on macOS: dotted-quad IPv4, and IPv6
/// in any RFC 4291 textual form, with an optional `%interface` zone.
enum AddressSyntax {
    /// Classifies an address, or returns `nil` when it is not a valid address.
    static func family(of text: String) -> AddressFamily? {
        if text.contains(":") {
            return isIPv6(text) ? .ipv6 : nil
        }
        return isIPv4(text) ? .ipv4 : nil
    }

    /// Leading zeros are refused: their base is ambiguous across implementations.
    static func isIPv4(_ text: String) -> Bool {
        let octets = text.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        for octet in octets {
            guard (1...3).contains(octet.count), octet.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
            if octet.count > 1 && octet.first == "0" { return false }
            guard let value = Int(octet), value <= 255 else { return false }
        }
        return true
    }

    static func isIPv6(_ text: String) -> Bool {
        var body = text
        if let zoneStart = text.firstIndex(of: "%") {
            let zone = text[text.index(after: zoneStart)...]
            guard !zone.isEmpty, zone.allSatisfy(isZoneCharacter) else { return false }
            body = String(text[..<zoneStart])
        }
        guard !body.isEmpty else { return false }

        let halves = body.components(separatedBy: "::")
        guard halves.count <= 2 else { return false }
        let compressed = halves.count == 2

        guard let head = groups(halves[0]), let tail = groups(compressed ? halves[1] : "") else { return false }

        // A final dotted quad stands for two groups.
        var hexGroups = head + tail
        var embeddedAddressGroups = 0
        if let last = hexGroups.last, last.contains(".") {
            guard isIPv4(String(last)) else { return false }
            embeddedAddressGroups = 2
            hexGroups.removeLast()
        }
        guard hexGroups.allSatisfy(isHexGroup) else { return false }

        let groupCount = hexGroups.count + embeddedAddressGroups
        return compressed ? groupCount < 8 : groupCount == 8
    }

    private static func groups(_ half: String) -> [Substring]? {
        guard !half.isEmpty else { return [] }
        let parts = half.split(separator: ":", omittingEmptySubsequences: false)
        return parts.contains(where: \.isEmpty) ? nil : parts
    }

    private static func isHexGroup(_ group: Substring) -> Bool {
        (1...4).contains(group.count) && group.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    private static func isZoneCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber
            || character == "." || character == "-" || character == "_"
    }
}
