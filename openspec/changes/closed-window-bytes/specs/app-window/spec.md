# Spec Delta

## MODIFIED Requirements

### Requirement: Closing the window releases what it built

Closing the window MUST release the window and everything it built — the
window, its hosting view, the fragment's text view, the resolved block's text
view and table — while the application keeps running in the menu bar. The
selection, an unsaved fragment draft and the last read MUST be kept, so
reopening the window shows what it showed. The resolved block MUST reopen in
text mode.

#### Scenario: A large table and the window closes
- **WHEN** the resolved block of 100,000 entries is shown as a table and the window is closed
- **THEN** no window, table, text view or text storage of the window remains in memory

#### Scenario: The window reopens
- **WHEN** the window is opened again after a close
- **THEN** the same item is selected, an unsaved draft is still there and still unsaved, and the resolved block is shown as text

### Requirement: The window's data exists while the window shows

The selected profile's composition, its rendered block's bytes, the selected
fragment's text and every parse the window's reads held MUST exist only while
the window is showing. Closing the window MUST let them go; the application
keeps running in the menu bar with, for each file, a digest of its bytes and
its entry count, and for each profile a digest of its rendered block and the
block's entry count — which is what the menu and the schedule read. It MUST
NOT keep a copy of a fragment, a rendered block or the live block. Reopening
the window MUST read in full again. A launch that shows no window MUST parse
no fragment for it.

#### Scenario: The window closes over a large profile
- **WHEN** the selected profile stacks a fragment of 100,000 entries and the window is closed
- **THEN** no composition, fragment parse, fragment bytes or rendered block of the window remains in memory, and the profile's entry count and rendering digest do

#### Scenario: The menu with the window closed
- **WHEN** the window is closed and the menu is opened, or a source is refreshed on its schedule
- **THEN** the store is read, the live file is read once, and no unchanged fragment is parsed

#### Scenario: The window reopens
- **WHEN** the window is opened again after a close
- **THEN** the selected profile's layers are parsed again and its block is shown, with the same selection and an unsaved draft still there and still unsaved

#### Scenario: Launched into the menu bar
- **WHEN** the application launches without showing its window
- **THEN** no fragment is parsed until the window is opened
