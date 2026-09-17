# Spec Delta

## Purpose

Edits the store from the window and explains what a profile resolves to, so a
profile can be authored inside the application while the live file still keeps
the guarantees the apply path already gives it.

## ADDED Requirements

### Requirement: The window edits the store

The window MUST list the store's profiles and fragments, MUST offer creating,
renaming, duplicating, and deleting both, and MUST read the store when it is
asked rather than presenting a cached list.

#### Scenario: A file added outside the application
- **WHEN** a fragment file is created by another tool and the window is refreshed
- **THEN** the fragment is listed

#### Scenario: No store yet
- **WHEN** no store exists
- **THEN** the window says so and offers to create the first profile rather than reporting a failure

### Requirement: Fragment text is edited as text

The window MUST present the selected fragment as editable plain text, MUST save
it through the store's authoring operations, and MUST report a save that fails
with its reason while leaving the previous text in the file.

#### Scenario: Round trip
- **WHEN** a fragment is edited and saved
- **THEN** the file holds the text that was saved and the next composition uses it

#### Scenario: The save is refused
- **WHEN** a save cannot be written
- **THEN** the reason is reported and the file keeps the text it had

### Requirement: A profile's layers are edited as an ordered stack

The window MUST show a profile's fragment references in order, MUST allow adding
a reference, removing a reference, and changing the order, and MUST write the
result as one fragment reference per line.

#### Scenario: Reordering changes the resolution
- **WHEN** two layers are reordered and the profile is saved
- **THEN** the resolution reflects the new order

#### Scenario: Every layer removed
- **WHEN** the last reference is removed and saved
- **THEN** the profile renders an empty block rather than failing

### Requirement: Malformed input is reported, not refused

Text composition cannot parse MUST be reported with the fragment and the line it
came from, MUST still be saveable, and MUST NOT contribute entries. A profile
that cannot be resolved MUST be reported as unresolvable rather than shown as a
partial or empty result.

#### Scenario: A malformed entry while editing
- **WHEN** a fragment holds a line that is not a host entry
- **THEN** the window names the fragment and the line and the save still succeeds

#### Scenario: A profile that cannot resolve
- **WHEN** a profile references a fragment the store does not hold
- **THEN** the window reports the missing fragment and shows no resolved entries

### Requirement: The resolved view explains the result from the store as it is now

The resolved view MUST be computed from the store's current text, MUST show every
resolved entry with the fragment that supplied it, and MUST show every entry
displaced by a conflict with the fragment that displaced it. Viewing MUST write
nothing.

#### Scenario: Source of an entry
- **WHEN** the resolved view is shown
- **THEN** every entry names the fragment it came from

#### Scenario: An override is explained
- **WHEN** a later layer overrides a hostname from an earlier layer
- **THEN** the view reports the displaced address, its fragment, and the fragment that won

#### Scenario: Viewing changes nothing
- **WHEN** the resolved view is shown
- **THEN** neither the store nor the live file is modified

### Requirement: An edit of the applied profile is re-applied over Hazmat's own bytes

When a save changes the profile whose block is live, the window MUST re-apply it
when the live block is still byte-identical to what that profile rendered before
the edit, and MUST leave the live file unchanged and report drift when the live
block differs from that. Editing a profile that is not applied MUST NOT change
the live file. A refused apply MUST leave the store change in place and report
the reason.

#### Scenario: Editing the applied profile
- **WHEN** a fragment of the applied profile is saved and the live block is still the block that profile rendered before the edit
- **THEN** the live file holds the newly rendered block and the outcome reports the change

#### Scenario: The block changed as well
- **WHEN** the live block differs from what the edited profile rendered before the edit
- **THEN** the live file is left as it is, drift is reported, and replacing the block is offered as its own action

#### Scenario: Editing an unapplied profile
- **WHEN** a profile that is not applied is edited
- **THEN** the live file's bytes and modification time are unchanged

#### Scenario: No approved helper
- **WHEN** the applied profile is edited while the helper is not approved
- **THEN** the store holds the edit, the live file is unchanged, and the refusal is reported with its reason

### Requirement: Store editing needs no privilege

Every store operation the window performs MUST succeed for an ordinary user
without privileged access. The only operation that may involve the helper is an
apply.

#### Scenario: Editing before the helper is approved
- **WHEN** a profile and a fragment are created while the helper is not registered
- **THEN** both are written to the store
