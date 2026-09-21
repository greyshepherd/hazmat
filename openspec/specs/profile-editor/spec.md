# profile-editor Specification

## Purpose

Edits the store from the window and explains what a profile resolves to, so a
profile can be authored inside the application while the live file still keeps
the guarantees the apply path already gives it.

## Requirements

### Requirement: The window edits the store

The window MUST list the store's profiles and fragments, MUST offer creating,
renaming, duplicating, and deleting both, and MUST read the store when it is
asked rather than presenting a cached list. Work derived from a file's bytes
(its parse, a profile's composition, its rendered block) MAY be reused between
reads only while the digest of the bytes read is identical to the digest they
were derived from; a file whose bytes changed MUST be parsed again on the next
read. A fragment's parse, a profile's composition and a rendered block's bytes
MUST be held between reads only while the window is showing; a digest of a
rendered block and an entry count MAY be held for as long as the bytes they
came from are unchanged. The bytes a read made MUST NOT be kept once the read
has answered.

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

#### Scenario: A fragment rewritten with different bytes of the same length
- **WHEN** a fragment file is rewritten within the same second with different bytes of the same length and the window is refreshed
- **THEN** the entry counts and the resolved view reflect the new bytes

#### Scenario: A large fragment no profile stacks
- **WHEN** the store holds a fragment of 100,000 entries that no profile stacks
- **THEN** its row states its entry count, and neither its parse nor its bytes are held between reads

#### Scenario: A profile comes to stack it
- **WHEN** a profile is edited to stack that fragment while the window is showing
- **THEN** the next read parses it and the profile composes over it

#### Scenario: A read for a closed window
- **WHEN** the store is read while the window is closed
- **THEN** the read carries the selected profile's entry count and the digest of its rendered block, and neither the block's bytes, its composition nor the selected fragment's text

### Requirement: Fragment text is edited as text

The window MUST present the selected fragment as editable plain text, MUST save
it through the store's authoring operations, and MUST report a save that fails
with its reason while leaving the previous text in the file. Editing MUST stay
responsive when the fragment holds 100,000 or more lines: a keystroke MUST NOT
re-read, re-parse or re-lay out the whole fragment. A fragment that records an
origin MUST be presented read-only, naming the URL it is fetched from and
carrying the action that refreshes it, because a later refresh replaces its text.

#### Scenario: Round trip
- **WHEN** a fragment is edited and saved
- **THEN** the file holds the text that was saved and the next composition uses it

#### Scenario: The save is refused
- **WHEN** a save cannot be written
- **THEN** the reason is reported and the file keeps the text it had

#### Scenario: Typing in a large fragment
- **WHEN** a fragment of 100,000 lines is selected and a character is typed
- **THEN** the character appears without a stall, the fragment reads as unsaved, and the store is unchanged until Save

#### Scenario: A fragment that is fetched from a URL
- **WHEN** a fragment with a recorded origin is selected
- **THEN** its text is shown read-only with the URL it comes from, and the refresh action is offered beside it

### Requirement: Remote sources are managed from the window

The window MUST offer adding a source by name, URL, and interval, and changing a
source's URL and interval afterwards. The sidebar MUST mark a fragment that
records an origin and MUST show the state of its last refresh: when it last
succeeded, and the reason of the last failure when there was one. A source whose
interval has elapsed since its last successful refresh, or which has never been
refreshed, MUST be shown as out of date. Refreshing a source on demand MUST be
offered on that source's own row, and a refresh it asks for MUST report its
outcome the way an edit does.

#### Scenario: Adding a source
- **WHEN** a name, an HTTPS URL, and an interval are given for a new source
- **THEN** the source is recorded, listed, and asked to refresh, and its fragment appears once text is fetched

#### Scenario: The sidebar marks a source
- **WHEN** the store holds a fragment with a recorded origin
- **THEN** its row is marked as fetched from a URL and names when it last refreshed

#### Scenario: Out of date
- **WHEN** a source's interval has elapsed since its last successful refresh
- **THEN** its row shows that it is out of date, and a fetch that succeeds clears that state

#### Scenario: The last failure is visible
- **WHEN** a source's last refresh failed
- **THEN** its row reports the reason the refresh gave

#### Scenario: Refresh on demand
- **WHEN** the refresh action is used on a source's row
- **THEN** the source is fetched and the outcome is reported

#### Scenario: A URL that is refused
- **WHEN** a URL that is not HTTPS or a body that is refused is given
- **THEN** the reason is reported and no source state is left claiming a successful refresh

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

### Requirement: The store's lists are readable, selectable rows

The window MUST list the store's profiles and fragments as rows in the sidebar,
MUST show which row is selected, and MUST make the selected row the item the
panes act on. A fragment row MUST show how many entries the fragment holds; a
profile row MUST show how many layers it stacks and whether its block is the live
one. Renaming and duplicating MUST be offered on the row they act on.

#### Scenario: Selection is visible
- **WHEN** a row is chosen
- **THEN** the row is shown as selected and the panes show that item

#### Scenario: A fragment row reports its size
- **WHEN** a fragment holding seven entries is listed
- **THEN** its row shows seven entries

#### Scenario: A profile row reports its stack and its state
- **WHEN** a profile stacking three layers is listed
- **THEN** its row shows three layers, and shows that it is applied when its block is the live one

#### Scenario: Renaming from the row
- **WHEN** rename is chosen for a row
- **THEN** the new name is written through the store's authoring operations and the row shows it

### Requirement: An empty list says what belongs in it and offers the action

Every empty list or pane MUST carry a label, a one-line description of what
belongs there, and the action that fills it. The window MUST NOT present an empty
list as a bare well.

#### Scenario: No profiles
- **WHEN** the store holds no profiles
- **THEN** the profiles section explains what a profile is and offers to create one

#### Scenario: No fragments
- **WHEN** the store holds no fragments
- **THEN** the fragments section explains what a fragment is and offers to create one

#### Scenario: A profile with no layers
- **WHEN** the selected profile stacks no layers
- **THEN** the layer list explains that layers are applied in order and offers to add the first one

### Requirement: A layer's effect and order are visible

A profile's layer list MUST show each layer in order, MUST show the number of
entries that layer contributes, MUST state the precedence rule that a later layer
wins a conflict, and MUST allow reordering without a dialog. The layer list MUST
NOT offer a control that keeps a layer in the stack while excluding it from
composition.

#### Scenario: Order is shown
- **WHEN** a profile stacking three layers is shown
- **THEN** each layer's position and entry count are shown, and the list states that a later layer wins

#### Scenario: Reordering by dragging
- **WHEN** a layer is dragged above another
- **THEN** the stack order is written to the store and the resolved block reflects the new order

#### Scenario: No off state
- **WHEN** the layer list is shown
- **THEN** each row offers reordering and removal, and no control that would leave the layer in the stack while excluding it

### Requirement: A fragment names the profiles that use it

Selecting a fragment MUST name the profiles whose stacks reference it, and MUST
say so plainly when none does.

#### Scenario: A fragment used by two profiles
- **WHEN** a fragment referenced by two profiles is selected
- **THEN** both profiles are named in the detail pane

#### Scenario: A fragment used by none
- **WHEN** a fragment no profile references is selected
- **THEN** the detail pane says that no profile uses it

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

### Requirement: Search narrows the store without hiding the selection

The window MUST filter the sidebar's profiles and fragments by the search text,
MUST keep the selected item selected while it still matches, and MUST select
nothing rather than a hidden item when it does not.

#### Scenario: The selection survives a search
- **WHEN** the selected fragment matches the search text
- **THEN** it stays selected and its text stays editable

#### Scenario: The selection is hidden by a search
- **WHEN** the selected item does not match the search text
- **THEN** the window shows that nothing matching is selected rather than editing a hidden item

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
