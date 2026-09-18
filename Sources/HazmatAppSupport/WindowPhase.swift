import Foundation

/// The phase the window is in, as one value: what the store holds, what the
/// selected profile resolves to, and what a write would do. The scene switches
/// on it instead of reading the parts itself.
public enum WindowPhase: Equatable, Sendable {
    case noStore
    case noProfiles
    case profileWithoutLayers
    case changesPending
    case inSync
    case blocked
    /// A search hid the selected item, so nothing matching is selected.
    case nothingSelected

    public init(editor: EditorPresentation, helper: HelperState) {
        if !editor.storeExists {
            self = .noStore
            return
        }
        if editor.profiles.isEmpty {
            self = .noProfiles
            return
        }
        guard editor.selectedProfile != nil else {
            self = .nothingSelected
            return
        }
        if editor.layers.isEmpty {
            self = .profileWithoutLayers
            return
        }
        switch editor.writeState(helper: helper) {
        case .inSync: self = .inSync
        case .pending: self = .changesPending
        case .blocked: self = .blocked
        }
    }

    /// The one prominently styled action the phase offers, and `nil` when the
    /// phase has nothing to promote.
    public func primaryAction(write: WriteState, helper: HelperState) -> WindowAction? {
        switch self {
        case .noStore: return .createStore
        case .noProfiles: return nil
        case .profileWithoutLayers: return nil
        case .changesPending: return .apply
        case .blocked: return write.remedy ?? (helper.canWrite ? nil : .installHelper)
        case .inSync, .nothingSelected: return nil
        }
    }

    public var title: String {
        switch self {
        case .noStore: return "No store yet"
        case .noProfiles: return "No profiles yet"
        case .profileWithoutLayers: return "This profile stacks no layers"
        case .changesPending: return "Changes are pending"
        case .inSync: return "In sync with the live file"
        case .blocked: return "Writing is blocked"
        case .nothingSelected: return "Nothing matching is selected"
        }
    }

    /// One line saying what belongs here, in the words the window shows.
    public var explanation: String {
        switch self {
        case .noStore:
            return "A store is a folder that holds your profiles and fragments. Nothing is written to /etc/hosts until you ask."
        case .noProfiles:
            return "A profile is an ordered stack of fragments. It resolves to the block Hazmat writes."
        case .profileWithoutLayers:
            return "Layers are applied in order, and a later layer wins a conflict. Adding one is the first step."
        case .changesPending:
            return "The selected profile renders a block the live file does not hold yet."
        case .inSync:
            return "The live block is byte-identical to what the selected profile renders."
        case .blocked:
            return "Something has to change before this profile can be written."
        case .nothingSelected:
            return "The search text does not match the selected item, so there is nothing to edit."
        }
    }
}
