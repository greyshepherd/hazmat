import ServiceManagement

/// What the app can say about the helper. Three states, because that is what the
/// app can act on.
public enum HelperState: String, CaseIterable, Equatable, Sendable {
    case notRegistered
    case awaitingApproval
    case enabled

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
