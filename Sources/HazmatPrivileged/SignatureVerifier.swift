import Foundation
import Security

public enum SignatureError: Error, Equatable, Sendable, CustomStringConvertible {
    case requirementUnreadable(String)
    case guestUnavailable(OSStatus)

    public var description: String {
        switch self {
        case .requirementUnreadable(let requirement):
            return "'\(requirement)' is not a readable code requirement"
        case .guestUnavailable(let status):
            return "the client's code could not be examined (\(status))"
        }
    }
}

/// Checks a client against a code requirement. Development cannot anchor to a
/// team, because an ad-hoc signature carries none, so the requirement is the
/// app's identifier alone; a shipping build anchors team and identifier.
public struct SignatureVerifier: Sendable {
    public let requirement: String

    public init(requirement: String) {
        self.requirement = requirement
    }

    public static func development(appIdentifier: String) -> SignatureVerifier {
        SignatureVerifier(requirement: "identifier \"\(appIdentifier)\"")
    }

    public static func shipping(appIdentifier: String, teamIdentifier: String) -> SignatureVerifier {
        SignatureVerifier(
            requirement: "identifier \"\(appIdentifier)\""
                + " and anchor apple generic"
                + " and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        )
    }

    /// Whether the process behind a connection satisfies the requirement. The
    /// identifier comes from the connection, not from the request, so a caller
    /// cannot name itself.
    public func accepts(processIdentifier: pid_t) -> Bool {
        guard let code = try? guestCode(processIdentifier: processIdentifier) else { return false }
        return accepts(code: code)
    }
    public func accepts(code: SecCode) -> Bool {
        guard let requirement = try? makeRequirement() else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private func makeRequirement() throws -> SecRequirement {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(self.requirement as CFString, [], &requirement)
        guard status == errSecSuccess, let requirement else {
            throw SignatureError.requirementUnreadable(self.requirement)
        }
        return requirement
    }

    private func guestCode(processIdentifier: pid_t) throws -> SecCode {
        let attributes = [kSecGuestAttributePid: NSNumber(value: processIdentifier)] as CFDictionary
        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard status == errSecSuccess, let code else {
            throw SignatureError.guestUnavailable(status)
        }
        return code
    }
}
