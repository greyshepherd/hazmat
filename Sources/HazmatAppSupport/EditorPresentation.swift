import Foundation
import HazmatCore

/// What the live file holds for the selected profile's block.
public enum LiveBlockState: Equatable, Sendable {
    /// The live file could not be read.
    case unreadable(reason: String)
    /// The file holds no managed block.
    case absent
    /// The file holds the block the selected profile renders now.
    case applied
    /// The file holds a well-formed block that differs from the rendering.
    case drifted(liveBlock: Data)
    /// The markers cannot be read as one supported block.
    case refused(BlockError)

    /// The block the file holds, when it holds a readable one.
    public var liveBlock: Data? {
        guard case .drifted(let block) = self else { return nil }
        return block
    }

    /// Whether the file holds a block at all.
    public var holdsABlock: Bool {
        switch self {
        case .absent, .unreadable: return false
        case .applied, .drifted, .refused: return true
        }
    }
}

/// The selected profile composed once: the surviving entries with their source
/// fragments, the entries a conflict displaced, or the problems that stopped
/// composition.
public enum ResolvedView: Equatable, Sendable {
    /// The profile composed.
    case composed(Composition)
    /// The profile cannot be resolved; it is reported rather than shown as a
    /// partial or empty result.
    case unresolvable([CompositionProblem])

    public var composition: Composition? {
        guard case .composed(let composition) = self else { return nil }
        return composition
    }

    public var entries: [ResolvedName] {
        composition?.resolved ?? []
    }

    public var displacements: [Displacement] {
        composition?.displacements ?? []
    }

    public var problems: [CompositionProblem] {
        guard case .unresolvable(let problems) = self else { return [] }
        return problems
    }

    /// The block the profile renders, or `nil` when it cannot be resolved.
    public var renderedBlock: Data? {
        composition.map(BlockRenderer.render)
    }
}

/// The window's whole state, read from the store and the live file when it is
/// asked for. The scene renders this value and forwards choices.
public struct EditorPresentation: Equatable, Sendable {
    /// What choosing a row or pressing a button asks the model to do.
    public enum Action: Equatable, Sendable {
        case newProfile
        case renameProfile(ProfileID)
        case duplicateProfile(ProfileID)
        case deleteProfile(ProfileID)
        case newFragment
        case renameFragment(FragmentID)
        case duplicateFragment(FragmentID)
        case deleteFragment(FragmentID)
        case saveFragment(FragmentID)
        case addLayer(ProfileID, FragmentID)
        case removeLayer(ProfileID, index: Int)
        case moveLayer(ProfileID, from: Int, to: Int)
        case applyProfile(ProfileID)
        case overwriteDrift(ProfileID, liveBlock: Data)
    }

    /// Where the store lives, for the window to name.
    public let storePath: String
    public let storeExists: Bool
    public let profiles: [ProfileID]
    public let fragments: [FragmentID]
    public let selectedProfile: ProfileID?
    public let selectedFragment: FragmentID?
    /// The selected fragment's text, as the store holds it now.
    public let fragmentText: String
    /// The selected profile's references, in order.
    public let layers: [FragmentID]
    /// The selected profile composed once, and rendered.
    public let resolved: ResolvedView
    /// What the live file holds for the selected profile's block.
    public let live: LiveBlockState
    /// Why the store could not be read, when it could not.
    public let storeProblem: String?
    /// The actions the window can offer in this state.
    public let actions: [Action]

    /// The block the selected profile renders now.
    public var rendering: Data? { resolved.renderedBlock }

    /// Whether the selected profile's block is the live one.
    public var isApplied: Bool { live == .applied }

    /// Whether the selected profile cannot be resolved, and why.
    public var problems: [CompositionProblem] { resolved.problems }

    /// The entries the selected profile resolves to, with their sources.
    public var entries: [ResolvedName] { resolved.entries }

    /// The entries a later layer displaced, with the fragment that displaced
    /// them.
    public var displacements: [Displacement] { resolved.displacements }
}
