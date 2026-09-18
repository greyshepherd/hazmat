import Foundation
import HazmatCore

/// What the window can be asked to do. The phase names the one prominent
/// action; the menus name all of them, so an action the window hides is still
/// reachable.
public enum WindowAction: Equatable, Sendable {
    case createStore
    case chooseLocation
    case newProfile
    case newFragment
    case apply
    case revert
    case overwriteDrift
    case removeBlock
    case reload
    case rename
    case duplicate
    case delete
    case save
    case installHelper
    /// Removes the registration and registers the helper again, for a helper
    /// that is registered but no longer answers.
    case repairHelper
    case revealHostsFile
    case toggleSidebar
    case search
    case showHelp
    /// Asks the update channel whether a newer version exists. Only a bundle that
    /// declares a feed offers it.
    case checkForUpdates

    /// Whether performing it asks the window for something: a name, a
    /// confirmation, a sheet, or the search field.
    public var presentsInTheWindow: Bool {
        switch self {
        case .createStore, .chooseLocation, .newProfile, .newFragment,
             .apply, .revert, .overwriteDrift, .removeBlock, .rename, .duplicate, .delete,
             .save, .installHelper, .search, .showHelp:
            return true
        case .reload, .repairHelper, .revealHostsFile, .toggleSidebar, .checkForUpdates:
            return false
        }
    }

    /// The words on the control that performs it.
    public var title: String {
        switch self {
        case .createStore: return "Create Store"
        case .chooseLocation: return "Choose Location…"
        case .newProfile: return "New Profile"
        case .newFragment: return "New Fragment"
        case .apply: return "Apply"
        case .revert: return "Revert"
        case .overwriteDrift: return "Overwrite the Drifted Block…"
        case .removeBlock: return "Remove the Block…"
        case .reload: return "Reload"
        case .rename: return "Rename"
        case .duplicate: return "Duplicate"
        case .delete: return "Delete"
        case .save: return "Save"
        case .installHelper: return "Install Helper…"
        case .repairHelper: return "Repair the Helper…"
        case .revealHostsFile: return "Reveal Hosts File"
        case .toggleSidebar: return "Toggle Sidebar"
        case .search: return "Search"
        case .showHelp: return "Hazmat Help"
        case .checkForUpdates: return "Check for Updates…"
        }
    }
}

/// What a write would do now: nothing, a pending change with the entries it
/// would hold, or a block with its cause and the action that resolves it.
public enum WriteState: Equatable, Sendable {
    case inSync
    case pending(entries: Int)
    case blocked(cause: String, remedy: WindowAction?)

    public static let inSyncLabel = "In sync"
    public static let blockedLabel = "Blocked"

    public var label: String {
        switch self {
        case .inSync: return Self.inSyncLabel
        case .pending(let entries): return "\(entries) \(entries == 1 ? "change" : "changes") pending"
        case .blocked: return Self.blockedLabel
        }
    }

    /// The line under the label: what would be written, or why it cannot be.
    public var detail: String {
        switch self {
        case .inSync:
            return "The live block is the block this profile renders."
        case .pending(let entries):
            return "Writing replaces the managed block with \(entries) \(entries == 1 ? "entry" : "entries")."
        case .blocked(let cause, _):
            return cause
        }
    }

    public var tone: StatusTone {
        switch self {
        case .inSync: return .success
        case .pending: return .warning
        case .blocked: return .danger
        }
    }

    public var symbolName: String {
        switch self {
        case .inSync: return "checkmark.circle"
        case .pending: return "arrow.triangle.2.circlepath"
        case .blocked: return "exclamationmark.triangle"
        }
    }

    public var isPending: Bool {
        if case .pending = self { return true }
        return false
    }

    public var entryCount: Int? {
        guard case .pending(let entries) = self else { return nil }
        return entries
    }

    public var remedy: WindowAction? {
        guard case .blocked(_, let remedy) = self else { return nil }
        return remedy
    }
}

extension EditorPresentation {
    /// What writing would do now, computed from the live block's state, the
    /// block the profile renders, and the helper. Nothing here is remembered:
    /// the same values always produce the same answer.
    public func writeState(helper: HelperState) -> WriteState {
        if !storeExists {
            return .blocked(cause: "There is no store at this location yet.", remedy: .createStore)
        }
        if let storeProblem {
            return .blocked(cause: storeProblem, remedy: nil)
        }
        guard profiles.isEmpty == false else {
            return .blocked(cause: "The store holds no profiles.", remedy: nil)
        }
        guard let selectedProfile else {
            return .blocked(cause: "No profile is selected.", remedy: nil)
        }
        guard !layers.isEmpty else {
            return .blocked(
                cause: "'\(selectedProfile)' stacks no layers, so there is nothing to write yet.",
                remedy: nil
            )
        }
        guard rendering != nil else {
            let reason = problems.isEmpty
                ? "'\(selectedProfile)' cannot be resolved."
                : problems.map(\.message).joined(separator: " ")
            return .blocked(cause: reason, remedy: nil)
        }

        switch live {
        case .applied:
            return .inSync
        case .absent, .drifted:
            guard helper.canWrite else {
                return .blocked(cause: helper.writeBlockCause, remedy: helper.remedy)
            }
            return .pending(entries: entryLines.count)
        case .refused(let error):
            return .blocked(cause: "The live file's markers cannot be read: \(error)", remedy: nil)
        case .unreadable(let reason):
            return .blocked(cause: "The live file could not be read: \(reason)", remedy: nil)
        }
    }
}
