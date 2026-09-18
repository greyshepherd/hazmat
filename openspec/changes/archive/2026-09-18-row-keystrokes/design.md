# Design

## Context

Three ways to give the window a keystroke without a menu bar item were measured
on a throwaway SwiftUI app of the same shape: a window holding a button and a
`TextEditor`.

- **A view-scoped `.keyboardShortcut`.** It works: a zero-size, invisible button
  fired on ⌘D and ⌘⌫ while the main menu held no item for either, so nothing
  appears in the menu bar. It also fires while the `TextEditor` has focus, and
  that is the problem: the event that would have been "delete to the start of the
  line" becomes the shortcut, and the text view never sees it. SwiftUI offers no
  way to make such a shortcut depend on what has focus.
- **A hidden `NSMenuItem` with `allowsKeyEquivalentWhenHidden`.** It keeps the
  menu's precedence and stays out of sight, but it is a menu bar item in
  everything but appearance: it needs a menu to live in, its enabled state has to
  follow the selection, and the application's menu bar is one value built in one
  place precisely so that nothing else adds items to it.
- **A local event monitor.** It runs before the keystroke is dispatched, so it
  can decide per event: answer it, or return it untouched. That is the only one
  of the three that can give ⌘⌫ back to the text system.

The third was measured the same way: with the `TextEditor` as first responder,
the monitor saw the keystroke, returned it, and the text view then deleted to the
start of the line. The keystroke arrives as `U+007F` with the command modifier
held, so both delete characters name the same key.

## Goals / Non-Goals

**Goals:**
- ⌘D and ⌘⌫ act on the selected row with no menu bar item, while the window
  showing that row is key.
- ⌘⌫ keeps its text-system meaning wherever the text system has it.
- Which keystroke maps to which action is a value with tests, not a decision
  buried in a view.

**Non-Goals:**
- Restoring a keystroke for rename, which the context menu offers without one.
- Making the keystrokes work with the window closed: both act on a row, and the
  window that shows rows is the point.
- Changing what duplicate or delete do once they are asked for.

## Decisions

**The rule lives in app support, the monitor in the shell.** `WindowShortcut`
holds the bindings — ⌘D for duplicate, ⌘⌫ for delete — and answers which action a
keystroke asks for given the modifiers and whether a text view has focus. The
yield is a property of the binding, so the rule is visible where the binding is
declared. The shell only turns an event into those values and performs the action,
which keeps the decision testable without a window.

**A keystroke is answered only while the window that shows the selection is key.**
The settings window, a sheet and the store chooser are all key at times, and none
of them shows the row a delete would remove. The guard needs the window's
identity rather than "is some window key", so the shell view hands the model the
window it is rendered in — a reader in the window plumbing file, not a second
claim about which window the application has.

**A kept keystroke is consumed.** The monitor returns nothing for a keystroke it
answers, so the text system cannot act on it as well; a keystroke it yields is
returned unchanged, so the text view sees exactly what it would have seen with no
monitor at all.

## Risks / Trade-offs

- A local monitor sees every keystroke the application dispatches → it reads the
  event into plain values first and compares exact modifiers, so only the two
  named combinations are answered and everything else is returned untouched.
- The window's identity arrives asynchronously, so the keystrokes are inert for
  the instant before the view reports its window → both act on a selection that
  only exists once the window has been drawn.
- The keystrokes stop working when the window is closed, where a menu item would
  have opened it → both act on a row, so there is nothing to act on without the
  window; the menu bar still offers neither command.
- ⌘D is answered while the fragment editor has focus, as it was when the menu
  item existed → no text binding uses ⌘D, and the alternative is a keystroke that
  works only in some of the window.
