# Spec Delta

## ADDED Requirements

### Requirement: Closing the window releases what it built

Closing the window MUST release the views the window built — the fragment's text
view, the resolved block's text view and table — while the application keeps
running in the menu bar. The selection, an unsaved fragment draft and the last
read MUST be kept, so reopening the window shows what it showed. The resolved
block MUST reopen in text mode.

#### Scenario: A large table and the window closes
- **WHEN** the resolved block of 100,000 entries is shown as a table and the window is closed
- **THEN** no table, text view or text storage of the window remains in memory

#### Scenario: The window reopens
- **WHEN** the window is opened again after a close
- **THEN** the same item is selected, an unsaved draft is still there and still unsaved, and the resolved block is shown as text
