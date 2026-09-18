import Foundation
import XCTest
@testable import HazmatAppSupport

/// The keystrokes the window answers without a menu bar item: which keystroke
/// asks for which action, and which one a text view keeps.
final class WindowShortcutTests: XCTestCase {
    private typealias Modifiers = CommandPresentation.Modifiers

    func testTheWindowAnswersDuplicateAndDelete() {
        XCTAssertEqual(
            WindowShortcut.bindings.map(\.action),
            [.duplicate, .delete],
            "the two commands that left the menu bar with the item-type menus"
        )
        XCTAssertEqual(WindowShortcut.bindings.map(\.shortcut.display), ["⌘D", "⌘⌫"])
    }

    func testCommandDuplicateIsAnsweredWhetherOrNotTextIsBeingEdited() {
        XCTAssertEqual(
            WindowShortcut.action(characters: "d", modifiers: .command, textEditing: false),
            .duplicate
        )
        XCTAssertEqual(
            WindowShortcut.action(characters: "d", modifiers: .command, textEditing: true),
            .duplicate,
            "no text binding uses ⌘D, so the window keeps it while someone types"
        )
    }

    func testCommandDeleteYieldsToATextViewAndIsAnsweredWithoutOne() {
        XCTAssertEqual(
            WindowShortcut.action(characters: "\u{7F}", modifiers: .command, textEditing: false),
            .delete
        )
        XCTAssertNil(
            WindowShortcut.action(characters: "\u{7F}", modifiers: .command, textEditing: true),
            "⌘⌫ deletes to the start of the line while someone is typing"
        )
        XCTAssertEqual(
            WindowShortcut.action(characters: "\u{8}", modifiers: .command, textEditing: false),
            .delete,
            "the backspace key delivers either delete character"
        )
    }

    func testOnlyTheNamedKeystrokesAreAnswered() {
        XCTAssertNil(WindowShortcut.action(characters: "d", modifiers: [], textEditing: false))
        XCTAssertNil(WindowShortcut.action(characters: "d", modifiers: [.command, .shift], textEditing: false))
        XCTAssertNil(WindowShortcut.action(characters: "D", modifiers: [.command, .option], textEditing: false))
        XCTAssertNil(WindowShortcut.action(characters: "k", modifiers: .command, textEditing: false))
        XCTAssertNil(WindowShortcut.action(characters: "\u{F728}", modifiers: .command, textEditing: false))
    }

    func testAShiftedKeystrokeIsNotTheNamedOne() {
        XCTAssertEqual(WindowShortcut.name(of: "D"), "d")

        XCTAssertNil(
            WindowShortcut.action(characters: "D", modifiers: [.command, .shift], textEditing: false),
            "⌘⇧D is not ⌘D"
        )
    }
}
