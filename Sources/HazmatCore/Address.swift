import Foundation

/// The address families a host entry can carry. A name resolving in both is a
/// union, not a conflict.
public enum AddressFamily: String, CaseIterable, Hashable, Sendable {
    case ipv4
    case ipv6
}

/// Address grammar as `/etc/hosts` uses it on macOS: dotted-quad IPv4, and IPv6
/// in any RFC 4291 textual form, with an optional `%interface` zone. The grammar
/// is ASCII-only, so it reads bytes; the `String` entry points are wrappers.
enum AddressSyntax {
    /// Classifies an address, or returns `nil` when it is not a valid address.
    static func family(of text: String) -> AddressFamily? {
        withBytes(of: text) { family(of: $0) }
    }

    static func family(of bytes: UnsafeRawBufferPointer) -> AddressFamily? {
        if bytes.contains(ASCII.colon) {
            return isIPv6(bytes) ? .ipv6 : nil
        }
        return isIPv4(bytes) ? .ipv4 : nil
    }

    /// Leading zeros are refused: their base is ambiguous across implementations.
    static func isIPv4(_ text: String) -> Bool {
        withBytes(of: text) { isIPv4($0) }
    }

    static func isIPv4(_ bytes: UnsafeRawBufferPointer) -> Bool {
        let octets = Lines.components(of: bytes, separatedBy: ".")
        guard octets.count == 4 else { return false }
        for octet in octets {
            guard (1...3).contains(octet.count), octet.allSatisfy(ASCII.isDigit) else { return false }
            if octet.count > 1 && octet[0] == ASCII.zero { return false }
            guard let value = decimal(octet), value <= 255 else { return false }
        }
        return true
    }

    static func isIPv6(_ text: String) -> Bool {
        withBytes(of: text) { isIPv6($0) }
    }

    static func isIPv6(_ bytes: UnsafeRawBufferPointer) -> Bool {
        var body = bytes
        if let zoneStart = bytes.firstIndex(of: ASCII.percent) {
            let zone = UnsafeRawBufferPointer(rebasing: bytes[(zoneStart + 1)...])
            guard !zone.isEmpty, zone.allSatisfy(isZoneCharacter) else { return false }
            body = UnsafeRawBufferPointer(rebasing: bytes[..<zoneStart])
        }
        guard !body.isEmpty else { return false }

        let halves = Lines.components(of: body, separatedBy: "::")
        guard halves.count <= 2 else { return false }
        let compressed = halves.count == 2

        guard let head = groups(halves[0]), let tail = groups(compressed ? halves[1] : nil) else { return false }

        // A final dotted quad stands for two groups.
        var hexGroups = head + tail
        var embeddedAddressGroups = 0
        if let last = hexGroups.last, last.contains(ASCII.dot) {
            guard isIPv4(last) else { return false }
            embeddedAddressGroups = 2
            hexGroups.removeLast()
        }
        guard hexGroups.allSatisfy(isHexGroup) else { return false }

        let groupCount = hexGroups.count + embeddedAddressGroups
        return compressed ? groupCount < 8 : groupCount == 8
    }

    private static func groups(_ half: UnsafeRawBufferPointer?) -> [UnsafeRawBufferPointer]? {
        guard let half, !half.isEmpty else { return [] }
        let parts = Lines.components(of: half, separatedBy: ":")
        return parts.contains(where: \.isEmpty) ? nil : parts
    }

    private static func isHexGroup(_ group: UnsafeRawBufferPointer) -> Bool {
        (1...4).contains(group.count) && group.allSatisfy(isHexDigit)
    }

    private static func isZoneCharacter(_ byte: UInt8) -> Bool {
        ASCII.isLetter(byte) || ASCII.isDigit(byte)
            || byte == ASCII.dot || byte == ASCII.dash || byte == ASCII.underscore
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        ASCII.isDigit(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
    }

    /// At most three digits, which is all an IPv4 octet holds.
    private static func decimal(_ bytes: UnsafeRawBufferPointer) -> Int? {
        var value = 0
        for byte in bytes {
            value = value * 10 + Int(byte - ASCII.zero)
        }
        return value
    }
}
