# Spec Delta

## ADDED Requirements

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
displaced entries and problems, and MUST write nothing while it is shown.

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
