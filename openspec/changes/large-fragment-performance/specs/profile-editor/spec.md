# Spec Delta

## MODIFIED Requirements

### Requirement: The window edits the store

The window MUST list the store's profiles and fragments, MUST offer creating,
renaming, duplicating, and deleting both, and MUST read the store when it is
asked rather than presenting a cached list. Work derived from a file's bytes
(its parse, a profile's composition, its rendered block) MAY be reused between
reads only while the bytes read are identical; a file whose bytes changed MUST
be parsed again on the next read.

#### Scenario: A file added outside the application
- **WHEN** a fragment file is created by another tool and the window is refreshed
- **THEN** the fragment is listed

#### Scenario: No store yet
- **WHEN** no store exists
- **THEN** the window says so and offers to create the first profile rather than reporting a failure

#### Scenario: A fragment changed outside the application
- **WHEN** a fragment file's bytes are changed by another tool and the window is refreshed
- **THEN** the entry counts, the resolved view and the layer rows reflect the changed bytes

#### Scenario: A fragment rewritten with the same bytes
- **WHEN** a fragment file is rewritten with byte-identical content and the window is refreshed
- **THEN** the window reads the file and presents the same result, whether or not it parsed the bytes again

### Requirement: The resolved block is readable as text or as a table

The detail pane MUST show the block the selected profile resolves to as selectable
monospaced text, MUST offer a table listing one entry per row with its address,
names and source fragment, MUST state the number of entries, MUST report
displaced entries and problems, and MUST write nothing while it is shown. Each of
these views MUST remain usable when the block holds 100,000 or more entries or
the displaced list holds tens of thousands of entries: the pane MUST lay out
only what is visible and MUST NOT stall the window to show them.

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

### Requirement: Fragment text is edited as text

The window MUST present the selected fragment as editable plain text, MUST save
it through the store's authoring operations, and MUST report a save that fails
with its reason while leaving the previous text in the file. Editing MUST stay
responsive when the fragment holds 100,000 or more lines: a keystroke MUST NOT
re-read, re-parse or re-lay out the whole fragment.

#### Scenario: Round trip
- **WHEN** a fragment is edited and saved
- **THEN** the file holds the text that was saved and the next composition uses it

#### Scenario: The save is refused
- **WHEN** a save cannot be written
- **THEN** the reason is reported and the file keeps the text it had

#### Scenario: Typing in a large fragment
- **WHEN** a fragment of 100,000 lines is selected and a character is typed
- **THEN** the character appears without a stall, the fragment reads as unsaved, and the store is unchanged until Save

## ADDED Requirements

### Requirement: The window stays responsive while the store is read

A read of the store and the live file MUST NOT stop the window from responding
to input. When a read is not immediate, the window MUST keep showing the
presentation it already had, MUST keep accepting input, and MUST show the
read's result when it completes. A read MUST NOT overwrite a draft the user is
editing, and a read that completes after a later read MUST NOT replace the
later read's result.

#### Scenario: A search keystroke over a large store
- **WHEN** the store holds a fragment of 100,000 entries and a character is typed into the search field
- **THEN** the character appears at once, and the narrowed lists follow when the read completes

#### Scenario: Selecting a profile that stacks a large fragment
- **WHEN** a profile stacking a fragment of 100,000 entries is selected
- **THEN** the selection is marked at once, and the resolved view follows when the read completes

#### Scenario: Two reads in flight
- **WHEN** a second read is asked for before the first completes
- **THEN** the window ends up showing the second read's result, whichever completes first

#### Scenario: A read lands over an edited draft
- **WHEN** a fragment's draft has unsaved edits and a read completes
- **THEN** the draft keeps the edits and still reads as unsaved
