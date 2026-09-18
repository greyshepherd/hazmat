# Tasks

## 1. The keystrokes as a value

- [x] 1.1 Add the two bindings — ⌘D for duplicate, ⌘⌫ for delete — with the yield rule per binding, and the lookup that answers which action a keystroke asks for; verify both delete characters name the same key, that wrong modifiers answer nothing, and that ⌘D is answered whether or not a text view has focus while ⌘⌫ is answered only without one

## 2. The window answers them

- [x] 2.1 Answer the keystrokes through a local event monitor in the shell, reading each event into plain values and consuming only what it answers; verify the model removes the monitor when it goes away
- [x] 2.2 Act only while the window the shell is rendered in is the key one, and only while no sheet or modal is up; verify the shell view reports its window and that another window being key leaves both keystrokes inert
- [x] 2.3 Give ⌘⌫ back while a text view has focus; verify with a focused text view that the text system performs its own binding
- [x] 2.4 Run the full test suite and verify it passes

## 3. Verification on the running bundle

- [x] 3.1 Build the development bundle, point it at a temporary store, and verify ⌘D asks for a duplicate's name and writes it while the menu bar carries no item for the keystroke
- [x] 3.2 Verify that ⌘⌫ with the search field focused clears the field's text and leaves every store file in place, and that the same keystroke with nothing focused deletes the selected row
