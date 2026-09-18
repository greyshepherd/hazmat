import Foundation

/// A keystroke the window answers on its own, with no menu bar item. The
/// item-type menus took their key equivalents with them, and a row's context
/// menu shows no keystroke, so these are the window's own.
public struct WindowShortcut: Equatable, Sendable {
    public let action: WindowAction
    /// The keystroke, named the way the menu bar named it.
    public let shortcut: CommandPresentation.Shortcut
    /// Whether a focused text view keeps the keystroke. ⌘⌫ deletes to the start
    /// of the line while someone is typing, which is worth more there than
    /// deleting the row they are editing.
    public let yieldsToTextEditing: Bool

    public init(
        action: WindowAction,
        shortcut: CommandPresentation.Shortcut,
        yieldsToTextEditing: Bool
    ) {
        self.action = action
        self.shortcut = shortcut
        self.yieldsToTextEditing = yieldsToTextEditing
    }

    /// The keystrokes the window answers: the two commands that left the menu bar
    /// with the menus, since both act on the row the sidebar shows.
    public static let bindings: [WindowShortcut] = [
        WindowShortcut(
            action: .duplicate,
            shortcut: CommandPresentation.Shortcut("d", .command),
            yieldsToTextEditing: false
        ),
        WindowShortcut(
            action: .delete,
            shortcut: CommandPresentation.Shortcut("delete", .command),
            yieldsToTextEditing: true
        )
    ]

    /// The action a keystroke asks for, `nil` when nothing binds it: a keystroke
    /// whose binding yields matches nothing while a text view has focus.
    public static func action(
        characters: String,
        modifiers: CommandPresentation.Modifiers,
        textEditing: Bool
    ) -> WindowAction? {
        let key = name(of: characters)
        return bindings.first { binding in
            binding.shortcut.key == key
                && binding.shortcut.modifiers == modifiers
                && !(textEditing && binding.yieldsToTextEditing)
        }?.action
    }

    /// The key a keystroke carries. The backspace key delivers either delete
    /// character depending on the modifiers held with it, and both mean `delete`.
    static func name(of characters: String) -> String {
        switch characters {
        case "\u{8}", "\u{7F}": return "delete"
        default: return characters.lowercased()
        }
    }
}
