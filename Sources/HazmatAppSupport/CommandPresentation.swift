import Foundation

/// The menu bar as a value: File, Edit, Hosts, Window and Help, each item's
/// shortcut, and whether this state can perform it. The scene renders it, so the
/// menu bar and the window act on the same model.
public struct CommandPresentation: Equatable, Sendable {
    public struct Shortcut: Equatable, Sendable {
        /// A character, or `delete` or `return`.
        public let key: String
        public let modifiers: Modifiers

        public init(_ key: String, _ modifiers: Modifiers) {
            self.key = key
            self.modifiers = modifiers
        }

        /// The words the menu shows, e.g. `⇧⌘N`.
        public var display: String {
            var text = ""
            if modifiers.contains(.control) { text += "⌃" }
            if modifiers.contains(.option) { text += "⌥" }
            if modifiers.contains(.shift) { text += "⇧" }
            if modifiers.contains(.command) { text += "⌘" }
            switch key {
            case "delete": text += "⌫"
            case "return": text += "⏎"
            default: text += key.uppercased()
            }
            return text
        }
    }

    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    public struct Item: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let shortcut: Shortcut?
        public let action: WindowAction
        public let isEnabled: Bool
        /// Whether the command asks the window for something (a name, a
        /// confirmation, the search field), so it still works with the window
        /// closed by opening the window first.
        public let needsTheWindow: Bool
    }

    public struct Menu: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let items: [Item]
    }

    public let menus: [Menu]

    /// The menu bar for the state the window is in. An item that cannot act in
    /// this state is still listed, so the action stays discoverable, and is
    /// reported as disabled so nothing unusable appears to work.
    ///
    /// The update check is the exception: a bundle that declares no feed is offered
    /// no check at all, because the only thing it could report is that it cannot
    /// check.
    public static func menuBar(
        editor: EditorPresentation,
        helper: HelperState,
        hasUnsavedEdit: Bool,
        update: UpdateAvailability = .unavailable
    ) -> CommandPresentation {
        let holdsABlock = editor.live.holdsABlock
        let pending = editor.writeState(helper: helper).isPending

        func item(
            _ id: String,
            _ title: String,
            _ action: WindowAction,
            _ shortcut: Shortcut? = nil,
            enabled: Bool = true
        ) -> Item {
            Item(
                id: id,
                title: title,
                shortcut: shortcut,
                action: action,
                isEnabled: enabled,
                needsTheWindow: action.presentsInTheWindow
            )
        }

        // The application menu carries the one command the settings scene does not
        // own: the platform adds the settings item itself, and a second one here
        // would be the same control twice.
        var application: [Item] = []
        if update != .unavailable {
            application.append(item("check-for-updates", "Check for Updates…", .checkForUpdates))
        }

        let menus = [
            Menu(id: "app", title: "Hazmat", items: application),
            Menu(id: "file", title: "File", items: [
                item("new-profile", "New Profile", .newProfile, Shortcut("n", .command)),
                item("new-fragment", "New Fragment", .newFragment, Shortcut("n", [.command, .shift])),
                item("new-source", "New Source…", .newSource, Shortcut("n", [.command, .option])),
                item("save", "Save Fragment", .save, Shortcut("s", .command), enabled: hasUnsavedEdit)
            ]),
            Menu(id: "edit", title: "Edit", items: [
                item("search", "Search", .search, Shortcut("f", .command))
            ]),
            Menu(id: "hosts", title: "Hosts", items: [
                item("apply", "Apply the Selected Profile", .apply, Shortcut("return", .command), enabled: pending),
                item("reveal", "Reveal Hosts File", .revealHostsFile, enabled: holdsABlock),
                item("reload", "Reload from Disk", .reload, Shortcut("r", .command)),
                item("remove-block", "Remove the Managed Block…", .removeBlock, enabled: holdsABlock),
                item("create-store", "Create Store", .createStore, enabled: !editor.storeExists),
                item("choose-location", "Choose Store Location…", .chooseLocation),
                item("install-helper", "Install the Helper…", .installHelper, enabled: helper.remedy == .installHelper),
                item("repair-helper", "Repair the Helper…", .repairHelper, enabled: helper.remedy == .repairHelper)
            ]),
            Menu(id: "window", title: "Window", items: [
                item("toggle-sidebar", "Toggle Sidebar", .toggleSidebar, Shortcut("s", [.command, .control]))
            ]),
            Menu(id: "help", title: "Help", items: [
                item("how-it-writes", "How Hazmat Writes to /etc/hosts", .showHelp)
            ])
        ]
        return CommandPresentation(menus: menus)
    }

    public func menu(_ id: String) -> Menu? {
        menus.first { $0.id == id }
    }

    public func item(_ id: String) -> Item? {
        menus.flatMap(\.items).first { $0.id == id }
    }
}
