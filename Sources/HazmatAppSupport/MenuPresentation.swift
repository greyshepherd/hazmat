import Foundation
import HazmatCore

/// The status item's title and menu. Built from what was read, the helper's
/// state, and the last outcome, so the scene renders decisions instead of
/// making them.
public struct MenuPresentation: Equatable, Sendable {
    /// What choosing an item asks the model to do.
    public enum Action: Equatable, Sendable {
        case activate(ProfileID)
        /// Replace a block that matches no profile. Deliberate: it is only ever
        /// offered as its own item, labelled with what it would write, and it
        /// names the drifted block the reading found.
        case overwriteDrift(ProfileID, liveBlock: Data)
        case turnOff
        case registerHelper
        case checkForUpdates
    }

    public struct Item: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        /// `nil` for a line: it reports and is not selectable.
        public let action: Action?
        public let isMarked: Bool

        public var isSelectable: Bool { action != nil }
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public let id: String
        public let items: [Item]
    }

    public let statusTitle: String
    public let sections: [Section]

    public init(
        reading: ActiveProfileReading,
        helper: HelperState,
        notice: String,
        update: UpdateAvailability = .unavailable
    ) {
        var items = ItemBuilder()

        var status: [Item] = [items.line(helper.summary)]
        if !notice.isEmpty {
            status.append(items.line(notice))
        }
        if case .failed(let reason) = update {
            status.append(items.line("Could not check for updates: \(reason)"))
        }
        if let activation = reading.activation {
            for problem in activation.problems {
                status.append(
                    items.line("profile '\(problem.profile)' could not be rendered: \(problem.reason)")
                )
            }
        }
        switch reading {
        case .missingStore:
            status.append(items.line("No store at this location."))
        case .emptyStore:
            status.append(items.line("The store holds no profiles."))
        case .unreadableFile(_, let reason):
            status.append(items.line("The live file could not be read: \(reason)"))
        case .derived(_, let activation):
            switch activation.state {
            case .off:
                status.append(items.line("No block is applied."))
            case .unreadable(let error):
                status.append(items.line("The live file's markers cannot be read: \(error)"))
            case .drifted:
                status.append(items.line("The live block matches no profile, so switching is refused."))
            case .active(let profiles):
                status.append(items.line("Active: \(profiles.map(\.rawValue).joined(separator: ", "))"))
            }
        }

        var profiles: [Item] = []
        var overwrites: [Item] = []
        let broken = Set(reading.activation?.problems.map(\.profile) ?? [])
        let active = Set(reading.activation?.activeProfiles ?? [])
        var driftedBlock: Data?
        if case .drifted(let block)? = reading.activation?.state {
            driftedBlock = block
        }
        for profile in reading.profiles where !broken.contains(profile) {
            profiles.append(items.item(profile.rawValue, .activate(profile), marked: active.contains(profile)))
            if let driftedBlock {
                overwrites.append(
                    items.item("Overwrite drift with '\(profile)'", .overwriteDrift(profile, liveBlock: driftedBlock))
                )
            }
        }

        var sections: [Section] = [Section(id: "status", items: status)]
        if !profiles.isEmpty {
            sections.append(Section(id: "profiles", items: profiles))
        }
        if !overwrites.isEmpty {
            sections.append(Section(id: "overwrite", items: overwrites))
        }
        sections.append(
            Section(id: "off", items: [items.item("Turn Hazmat Off", .turnOff)])
        )
        if !helper.canWrite {
            sections.append(
                Section(id: "helper", items: [items.item("Register Helper", .registerHelper)])
            )
        }
        if update != .unavailable {
            sections.append(
                Section(id: "updates", items: [items.item("Check for Updates…", .checkForUpdates)])
            )
        }

        statusTitle = Self.title(for: reading)
        self.sections = sections
    }

    /// Names the state rather than a remembered profile: a remembered name lies
    /// as soon as another tool edits the file.
    private static func title(for reading: ActiveProfileReading) -> String {
        switch reading {
        case .missingStore:
            return "Hazmat: no store"
        case .emptyStore:
            return "Hazmat: no profiles"
        case .unreadableFile:
            return "Hazmat: unreadable"
        case .derived(_, let activation):
            switch activation.state {
            case .off:
                return "Hazmat: off"
            case .unreadable:
                return "Hazmat: markers refused"
            case .drifted:
                return "Hazmat: drift"
            case .active(let profiles):
                return "Hazmat: \(profiles.map(\.rawValue).joined(separator: ", "))"
            }
        }
    }
}

/// Numbering keeps item identity stable while a presentation is rebuilt.
private struct ItemBuilder {
    private var counter = 0

    mutating func line(_ title: String) -> MenuPresentation.Item {
        counter += 1
        return MenuPresentation.Item(id: "line:\(counter)", title: title, action: nil, isMarked: false)
    }

    mutating func item(
        _ title: String,
        _ action: MenuPresentation.Action,
        marked: Bool = false
    ) -> MenuPresentation.Item {
        counter += 1
        return MenuPresentation.Item(id: "item:\(counter)", title: title, action: action, isMarked: marked)
    }
}
