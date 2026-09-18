import Foundation
import HazmatProtocol
import Security

public enum SignatureError: Error, Equatable, Sendable, CustomStringConvertible {
    case requirementUnreadable(String)

    public var description: String {
        switch self {
        case .requirementUnreadable(let requirement):
            return "'\(requirement)' is not a readable code requirement"
        }
    }
}

/// Builds the code requirement a client must satisfy. Development cannot anchor
/// to a team, because an ad-hoc signature carries none, so the requirement is
/// the app's identifier alone; a shipping build anchors team and identifier.
///
/// The requirement is handed to the connection, and the system checks the
/// process behind every message against it. Nothing here looks a process up by
/// its identifier: a process identifier can be reused, and a check made against
/// one at accept time says nothing about who sends the next message.
public struct SignatureVerifier: Sendable {
    public let requirement: String

    public init(requirement: String) {
        self.requirement = requirement
    }

    public static func development(appIdentifier: String) -> SignatureVerifier {
        SignatureVerifier(requirement: "identifier \"\(appIdentifier)\"")
    }

    /// The requirement for the build that is actually running. A distribution
    /// build carries a team in its own signature, and then the team is part of
    /// what a client must satisfy, so an ad-hoc build of the same identifier
    /// cannot write. A development build carries no team, and there is nothing to
    /// anchor but the identifier. Deriving it from the running binary means the
    /// rule cannot disagree with how that binary was signed.
    public static func forOwnBundle(appIdentifier: String = HazmatIdentity.bundleIdentifier) -> SignatureVerifier {
        guard let teamIdentifier = ownTeamIdentifier() else {
            return .development(appIdentifier: appIdentifier)
        }
        return .shipping(appIdentifier: appIdentifier, teamIdentifier: teamIdentifier)
    }

    /// The team the running process was signed with, or nothing when it was
    /// signed ad-hoc.
    private static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let signed = information as? [String: Any],
              let team = signed[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty
        else {
            return nil
        }
        return team
    }

    public static func shipping(appIdentifier: String, teamIdentifier: String) -> SignatureVerifier {
        SignatureVerifier(
            requirement: "identifier \"\(appIdentifier)\""
                + " and anchor apple generic"
                + " and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        )
    }

    /// The requirement as text the system can read, or the reason it cannot. A
    /// connection given an unreadable requirement raises rather than refuses, so
    /// it is read here first.
    public func readableRequirement() throws -> String {
        _ = try makeRequirement()
        return requirement
    }

    /// Whether `code` satisfies the requirement. What the connection's own check
    /// decides, made callable so the requirement's meaning can be tested.
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
}
