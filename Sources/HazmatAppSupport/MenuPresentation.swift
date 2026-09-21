import Foundation
import HazmatCore

/// The menu, and the name the status item reads out: built from what was read,
/// the helper's state, and the last outcome, so the scenes render decisions
/// instead of making them.
public struct MenuPresentation: Equatable, Sendable {
    /// What choosing an item asks the model to do.
    public enum Action: Equatable, Sendable {
        case activate(ProfileID)
        /// Replace a block that matches no profile. Deliberate: it is only ever
        /// offered as its own item, labelled with what it would write, and it
        /// names the drifted block the reading found.
        case overwriteDrift(ProfileID, block: ByteDigest)
        case turnOff
        case registerHelper
        /// Remove the registration and register the helper again.
        case repairHelper
        /// Ask the update channel whether a newer version exists. Only offered
        /// when the bundle declares a feed.
        case checkForUpdates
        /// Bring the main window forward.
        case openWindow
        /// End the application.
        case quit
    }

    public struct Item: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        /// `nil` for a line: it reports and is not selectable.
        public let action: Action?
        public let isMarked: Bool
        /// The keystroke the item carries in the menu, when it has one.
        public let shortcut: CommandPresentation.Shortcut?

        public init(
            id: String,
            title: String,
            action: Action?,
            isMarked: Bool,
            shortcut: CommandPresentation.Shortcut? = nil
        ) {
            self.id = id
            self.title = title
            self.action = action
            self.isMarked = isMarked
            self.shortcut = shortcut
        }

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
        notice: MenuNotice,
        update: UpdateAvailability = .unavailable
    ) {
        var items = ItemBuilder()

        // What needs attention, and nothing else: a healthy helper, an applied
        // block, a state the marks already carry, and a successful write are
        // all silent. A quiet menu means everything is as the items say.
        var status: [Item] = []
        if helper != .enabled {
            status.append(items.line(helper.summary))
        }
        if case .failure(let text) = notice {
            status.append(items.line(text))
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
            case .off, .active:
                break
            case .unreadable(let error):
                status.append(items.line("The live file's markers cannot be read: \(error)"))
            case .drifted:
                status.append(items.line("The live block matches no profile, so switching is refused."))
            }
        }

        var profiles: [Item] = []
        var overwrites: [Item] = []
        let broken = Set(reading.activation?.problems.map(\.profile) ?? [])
        let active = Set(reading.activation?.activeProfiles ?? [])
        var driftedBlock: ByteDigest?
        if case .drifted(let block)? = reading.activation?.state {
            driftedBlock = block
        }
        for profile in reading.profiles where !broken.contains(profile) {
            profiles.append(items.item(profile.rawValue, .activate(profile), marked: active.contains(profile)))
            if let driftedBlock {
                overwrites.append(
                    items.item("Overwrite drift with '\(profile)'", .overwriteDrift(profile, block: driftedBlock))
                )
            }
        }

        var sections: [Section] = []
        if !status.isEmpty {
            sections.append(Section(id: "status", items: status))
        }
        if !profiles.isEmpty {
            sections.append(Section(id: "profiles", items: profiles))
        }
        if !overwrites.isEmpty {
            sections.append(Section(id: "overwrite", items: overwrites))
        }
        sections.append(
            Section(id: "off", items: [items.item("Turn Hazmat Off", .turnOff)])
        )
        if let remedy = helper.remedy {
            let repairing = remedy == .repairHelper
            sections.append(
                Section(
                    id: "helper",
                    items: [
                        items.item(
                            repairing ? "Repair Helper" : "Register Helper",
                            repairing ? .repairHelper : .registerHelper
                        )
                    ]
                )
            )
        }
        if update != .unavailable {
            sections.append(
                Section(id: "updates", items: [items.item("Check for Updates…", .checkForUpdates)])
            )
        }
        sections.append(
            Section(
                id: "app",
                items: [
                    items.item("Open Hazmat", .openWindow),
                    items.item("Quit Hazmat", .quit, shortcut: CommandPresentation.Shortcut("q", .command)),
                ]
            )
        )

        statusTitle = Self.title(for: reading)
        self.sections = sections
    }

    /// Names the state rather than a remembered profile: a remembered name lies
    /// as soon as another tool edits the file. Public so the mark can read out
    /// the state without building the menu around it.
    public static func title(for reading: ActiveProfileReading) -> String {
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
        marked: Bool = false,
        shortcut: CommandPresentation.Shortcut? = nil
    ) -> MenuPresentation.Item {
        counter += 1
        return MenuPresentation.Item(id: "item:\(counter)", title: title, action: action, isMarked: marked, shortcut: shortcut)
    }
}
