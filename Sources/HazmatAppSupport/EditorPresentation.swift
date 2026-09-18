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

/// A profile as a sidebar row: how many layers it stacks, and whether its block
/// is the live one.
public struct ProfileRow: Equatable, Sendable, Identifiable {
    public let profile: ProfileID
    public let layerCount: Int
    public let isApplied: Bool

    public var id: ProfileID { profile }
}

/// A fragment as a sidebar row: the entries it holds.
public struct FragmentRow: Equatable, Sendable, Identifiable {
    public let fragment: FragmentID
    public let entryCount: Int

    public var id: FragmentID { fragment }
}

/// A layer of the selected profile: its position in the stack and the entries
/// its fragment holds.
public struct LayerRow: Equatable, Sendable, Identifiable {
    public let fragment: FragmentID
    /// One-based position in the stack.
    public let position: Int
    public let entryCount: Int

    public var id: String { "\(position)-\(fragment.rawValue)" }
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

    /// What the content pane shows. The selected item wins: a store that holds
    /// only fragments still edits the selected fragment, so no phase can hide
    /// it. The phase fills the pane when nothing is selected.
    public enum Content: Equatable, Sendable {
        case fragment(FragmentID)
        case profile(ProfileID)
        case phase(WindowPhase)
    }

    /// The item the content pane edits, or the phase when there is nothing to
    /// edit.
    public func content(phase: WindowPhase) -> Content {
        switch selection {
        case .fragment(let fragment): return .fragment(fragment)
        case .profile(let profile): return .profile(profile)
        case nil: return .phase(phase)
        }
    }

    /// Where the store lives, for the window to name.
    public let storePath: String
    /// The live file, so a confirmation can name what it would write.
    public let hostsFilePath: String
    public let storeExists: Bool
    /// Everything the store holds, whether or not the search matches it.
    public let profiles: [ProfileID]
    public let fragments: [FragmentID]
    /// The profiles the search matched, in sidebar order.
    public let profileRows: [ProfileRow]
    /// The fragments the search matched, in sidebar order.
    public let fragmentRows: [FragmentRow]
    /// The profile the window acts on: the selected one, or the first the
    /// search matched.
    public let selectedProfile: ProfileID?
    /// The fragment the window acts on: the selected one, or the first the
    /// search matched.
    public let selectedFragment: FragmentID?
    /// What the content pane edits. `nil` when a search hid the selection.
    public let selection: SidebarSelection?
    /// The selection a search hid, so the window can say which item it was.
    public let hiddenSelection: SidebarSelection?
    /// The search this read was narrowed by.
    public let search: StoreSearch
    /// The selected fragment's text, as the store holds it now.
    public let fragmentText: String
    /// The selected profile's references, in order.
    public let layers: [FragmentID]
    /// The selected profile's layers, with their positions and entry counts.
    public let layerRows: [LayerRow]
    /// The selected profile composed once, and rendered.
    public let resolved: ResolvedView
    /// The block's entry lines: one row per address line the renderer writes.
    public let entryLines: [BlockEntry]
    /// The profiles whose stack references the selected fragment.
    public let usingProfiles: [ProfileID]
    /// The profiles whose rendering is the live block.
    public let appliedProfiles: [ProfileID]
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

    /// How many entries the block would hold: one per address line.
    public var entryCount: Int { entryLines.count }

    /// How many layers the selected profile stacks.
    public var layerCount: Int { layers.count }

    /// The entries the fragment holds, as its row and its layer row show them.
    public func entryCount(of fragment: FragmentID) -> Int? {
        fragmentRows.first { $0.fragment == fragment }?.entryCount
    }

    /// Whether the given profile's block is the live one.
    public func isApplied(_ profile: ProfileID) -> Bool {
        appliedProfiles.contains(profile)
    }
}
