import ServiceManagement

/// What the app can say about the helper. Three states, because that is what the
/// app can act on.
public enum HelperState: String, CaseIterable, Equatable, Sendable {
    case notRegistered
    case awaitingApproval
    case enabled

    /// The word the sidebar footer shows beside the glyph.
    public var label: String {
        switch self {
        case .notRegistered: return "Helper not installed"
        case .awaitingApproval: return "Helper needs approval"
        case .enabled: return "Writes ready"
        }
    }

    /// The glyph the footer shows. Never colour alone: a state carries a glyph
    /// and a word as well.
    public var symbolName: String {
        switch self {
        case .notRegistered: return "exclamationmark.triangle"
        case .awaitingApproval: return "hourglass"
        case .enabled: return "checkmark.seal"
        }
    }

    public var tone: StatusTone {
        switch self {
        case .enabled: return .success
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
        }
    }

    /// The action that resolves this state, when one does.
    public var remedy: WindowAction? {
        canWrite ? nil : .installHelper
    }

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
            StateNote(state: .enabled, detail: "Approved and ready; Hazmat can write the block when you apply.")
        ]
    }
}
