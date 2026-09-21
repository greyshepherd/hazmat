# Spec Delta

## ADDED Requirements

### Requirement: The window's data exists while the window shows

The selected profile's composition, the selected fragment's text and every
parse the window's reads held MUST exist only while the window is showing.
Closing the window MUST let them go; the application keeps running in the menu
bar with each profile's rendered block, the files' bytes and the entry counts,
which is what the menu and the schedule read. Reopening the window MUST read
in full again. A launch that shows no window MUST parse no fragment for it.

#### Scenario: The window closes over a large profile
- **WHEN** the selected profile stacks a fragment of 100,000 entries and the window is closed
- **THEN** no composition or fragment parse of the window remains in memory, and the profile's rendered block does

#### Scenario: The menu with the window closed
- **WHEN** the window is closed and the menu is opened, or a source is refreshed on its schedule
- **THEN** the store is read and no unchanged fragment is parsed

#### Scenario: The window reopens
- **WHEN** the window is opened again after a close
- **THEN** the selected profile's layers are parsed again and its block is shown, with the same selection and an unsaved draft still there and still unsaved

#### Scenario: Launched into the menu bar
- **WHEN** the application launches without showing its window
- **THEN** no fragment is parsed until the window is opened
