# Spec Delta

## MODIFIED Requirements

### Requirement: The resolved block is readable as text or as a table

The detail pane MUST show the block the selected profile resolves to as selectable
monospaced text, MUST offer a table listing one entry per row with its address,
names and source fragment, MUST state the number of entries, MUST report
displaced entries and problems, and MUST write nothing while it is shown. Each of
these views MUST remain usable when the block holds 100,000 or more entries or
the displaced list holds tens of thousands of entries: the pane MUST lay out
only what is visible, MUST NOT stall the window to show them, and MUST NOT hold
a view for an entry that is not on screen.

#### Scenario: Text view
- **WHEN** the resolved block is shown as text
- **THEN** the lines can be selected and copied, and the entry count is stated

#### Scenario: Table view
- **WHEN** the resolved block is shown as a table
- **THEN** each row names the address, the names on it and the fragment that supplied it

#### Scenario: An override is explained
- **WHEN** a later layer overrides a hostname from an earlier layer
- **THEN** the displaced entry, its fragment and the fragment that won are all shown

#### Scenario: A profile that cannot resolve
- **WHEN** the profile references a fragment the store does not hold or holds a malformed line
- **THEN** the problem is reported with its fragment and line instead of entries

#### Scenario: Viewing changes nothing
- **WHEN** the resolved block is shown
- **THEN** neither the store nor the live file is modified

#### Scenario: A block of a hundred thousand entries
- **WHEN** the selected profile resolves to 100,000 entries and 50,000 displaced entries
- **THEN** the text view, the table view and the displaced list each open and scroll without stalling the window, and the entry count is stated

#### Scenario: A table of a hundred thousand entries
- **WHEN** the resolved block of 100,000 entries is shown as a table
- **THEN** the table reports 100,000 rows and holds views for the rows on screen only
