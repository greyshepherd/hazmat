import ServiceManagement

/// What the app can say about the helper. Four states, because that is what the
/// app can act on: the three the registration reports, and one for a helper that
/// is registered and approved but does not answer.
public enum HelperState: String, CaseIterable, Equatable, Sendable {
    case notRegistered
    case awaitingApproval
    case enabled
    /// Approved, and no answer came back from a check for it.
    case notAnswering

    /// The word the sidebar footer shows beside the glyph.
    public var label: String {
        switch self {
        case .notRegistered: return "Helper not installed"
        case .awaitingApproval: return "Helper needs approval"
        case .enabled: return "Writes ready"
        case .notAnswering: return "Helper not answering"
        }
    }

    /// The glyph the footer shows. Never colour alone: a state carries a glyph
    /// and a word as well.
    public var symbolName: String {
        switch self {
        case .notRegistered: return "exclamationmark.triangle"
        case .awaitingApproval: return "hourglass"
        case .enabled: return "checkmark.seal"
        case .notAnswering: return "bolt.slash"
        }
    }

    public var tone: StatusTone {
        switch self {
        case .enabled: return .success
        case .notAnswering: return .danger
        case .notRegistered, .awaitingApproval: return .warning
        }
    }

    public var summary: String {
        switch self {
        case .notRegistered:
            return "The helper is not registered. Register it to allow writes."
        case .awaitingApproval:
            return "The helper is registered and waiting for approval in System Settings > General > Login Items & Extensions."
        case .enabled:
            return "The helper is approved and can write the hosts file."
        case .notAnswering:
            return "The helper is registered and approved, but it did not answer. Repair it to register it again."
        }
    }

    public var canWrite: Bool { self == .enabled }

    /// Why a write cannot happen in this state, for the blocked write state.
    public var writeBlockCause: String {
        switch self {
        case .notRegistered:
            return "The helper is not installed, so nothing can write the hosts file."
        case .awaitingApproval:
            return "The helper is waiting for approval in System Settings, so the hosts file cannot be written yet."
        case .enabled:
            return "The hosts file can be written."
        case .notAnswering:
            return "The helper is registered but did not answer, so the hosts file cannot be written. Repairing the helper registers it again."
        }
    }

    /// The action that resolves this state, when one does.
    public var remedy: WindowAction? {
        switch self {
        case .enabled: return nil
        case .notAnswering: return .repairHelper
        case .notRegistered, .awaitingApproval: return .installHelper
        }
    }

    /// What the approval alone says: the registration's own three answers. Whether
    /// the helper answers is the other half, in `state(for:reachability:)`.
    ///
    /// `notFound` means the bundle does not hold a readable property list, so
    /// nothing is registered either way.
    public static func state(for status: SMAppService.Status) -> HelperState {
        switch status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .awaitingApproval
        case .notRegistered, .notFound:
            return .notRegistered
        @unknown default:
            return .notRegistered
        }
    }

    /// The state a check for the helper refines. Only an approved helper can be
    /// one that does not answer, so a helper that is not registered or not yet
    /// approved keeps the registration's own word.
    public func refined(by reachability: HelperReachability) -> HelperState {
        guard self == .enabled else { return self }
        return reachability == .answering ? .enabled : .notAnswering
    }

    /// The state the window shows: the approval first, and a check only refines
    /// it.
    public static func state(for status: SMAppService.Status, reachability: HelperReachability) -> HelperState {
        state(for: status).refined(by: reachability)
    }
}

/// What a check for the helper found.
public enum HelperReachability: Equatable, Sendable {
    /// The helper answered.
    case answering
    /// Nothing answered within the time allowed. A registered helper the system
    /// can no longer start looks exactly like this from the app's side.
    case silent
    /// The connection failed before any reply arrived: the helper refused this
    /// app, or no service is registered for it.
    case refused(reason: String)
}

/// The helper sheet: the privileges the helper holds, and the states it can be
/// in. Words come from here so the scene renders rather than explains.
public struct HelperSheetPresentation: Equatable, Sendable {
    public struct Privilege: Equatable, Sendable, Identifiable {
        public let id: String
        public let detail: String
    }

    public struct StateNote: Equatable, Sendable, Identifiable {
        public let state: HelperState
        public let detail: String

        public var id: String { state.rawValue }
    }

    public let current: HelperState
    public let privileges: [Privilege]
    public let states: [StateNote]

    public init(current: HelperState) {
        self.current = current
        privileges = [
            Privilege(
                id: "block",
                detail: "Writes only the block between the two Hazmat markers, and keeps every byte outside them as it was."
            ),
            Privilege(
                id: "caller",
                detail: "Accepts requests only from Hazmat, and only for the one file at /etc/hosts."
            ),
            Privilege(
                id: "removable",
                detail: "Installs as a launchd service you can remove at any time in System Settings."
            )
        ]
        states = [
            StateNote(state: .notRegistered, detail: "Nothing is installed; the store is fully editable and no write can happen."),
            StateNote(state: .awaitingApproval, detail: "Registered and waiting for you to allow it in Login Items & Extensions."),
            StateNote(state: .enabled, detail: "Approved, answering, and ready; Hazmat can write the block when you apply."),
            StateNote(state: .notAnswering, detail: "Registered and approved, but the helper did not answer. Repairing it removes the registration and registers it again.")
        ]
    }
}
