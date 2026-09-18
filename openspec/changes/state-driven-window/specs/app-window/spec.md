# Spec Delta

## Purpose

The application window: it shows the store, the thing being edited, and the block
that will be written, in one place; it derives what it offers from the state of
the store and the live file; and it carries the brand's colour and contrast rules.

## ADDED Requirements

### Requirement: The window presents the store, the selected item and the resolved block together

The window MUST present three panes at once: a sidebar listing the store's
profiles and fragments, a content pane editing the selected item, and a detail
pane showing the block the selected profile resolves to. Choosing an item in the
sidebar MUST change the content and detail panes to that item without leaving the
window. The window MUST NOT require scrolling from one pane to reach another.

#### Scenario: A profile is selected
- **WHEN** a profile row is chosen in the sidebar
- **THEN** the content pane shows that profile's layers and the detail pane shows the block it resolves to

#### Scenario: A fragment is selected
- **WHEN** a fragment row is chosen in the sidebar
- **THEN** the content pane edits that fragment's text and the detail pane shows the profiles that use it

#### Scenario: Nothing is selected
- **WHEN** the store holds nothing to select
- **THEN** each pane says what it would show rather than rendering an empty rectangle

### Requirement: Every phase of use offers one primary action

The window MUST derive its content and its actions from the state of the store,
the selected profile and the live file, and MUST present exactly one prominently
styled action for the phase: creating the store, creating the first profile,
adding a layer, applying, or installing the helper. The write action MUST be
absent when there is nothing to write.

#### Scenario: No store yet
- **WHEN** no store exists at the resolved location
- **THEN** the window explains what a store is, names the location as a copyable path, shows the three setup steps, and offers creating the store as its only prominent action

#### Scenario: Store with no profiles
- **WHEN** the store exists and holds no profiles
- **THEN** the sidebar shows both sections empty and the content pane explains what a profile is, offering creating one as its only prominent action

#### Scenario: A profile with no layers
- **WHEN** a profile is selected and stacks no layers
- **THEN** the content pane explains layering, the detail pane reports that there is nothing to write yet, and adding a fragment is the only prominent action

#### Scenario: In sync
- **WHEN** the live block is byte-identical to the selected profile's rendering
- **THEN** the window reports that it is in sync and offers no write

### Requirement: Unusable controls are not permanent chrome

An action that cannot act in the current state MUST NOT be presented as a
permanently disabled control in the window's content. It MUST appear where it
applies: in the toolbar, in the row's context menu, or in the pane it acts on,
and it MUST be offered only when it can act.

#### Scenario: Nothing selected
- **WHEN** no profile is selected
- **THEN** rename, duplicate, delete and apply for a profile are not offered anywhere in the window

#### Scenario: A fragment that cannot be saved
- **WHEN** no fragment is selected
- **THEN** no save control is presented

### Requirement: The window reports what a write would change

The window MUST report the write state as one of in sync, changes pending, or
blocked. A pending state MUST name the number of entries the block to be written
would hold. A blocked state MUST name why the write cannot happen and the action
that resolves it.

#### Scenario: Changes pending
- **WHEN** a layer is reordered so the rendering differs from the live block
- **THEN** the write state reads as pending and names the entries that would be written

#### Scenario: Blocked without an approved helper
- **WHEN** a write is pending and the helper is not enabled
- **THEN** the write state reads as blocked, names the helper as the cause, and offers the action that resolves it

#### Scenario: Off
- **WHEN** the selected profile renders a block and the live file holds none
- **THEN** the write state reads as pending rather than in sync

### Requirement: Writing is confirmed and can be reverted

The window MUST NOT write the live file without a confirmation that names the
file and the number of entries to be written. The window MUST keep the block an
apply replaced, MUST offer to restore it, and MUST refuse the restore with a
reason when the live file changed after the apply.

#### Scenario: A confirmation names the change
- **WHEN** the write is started
- **THEN** a confirmation names the hosts file and the number of entries it would hold before anything is written

#### Scenario: The confirmation is cancelled
- **WHEN** the confirmation is cancelled
- **THEN** the live file is unchanged and the write state stays pending

#### Scenario: The change is reverted
- **WHEN** the restore is chosen after an apply that replaced a block
- **THEN** the live file holds the block it held before that apply

#### Scenario: The file changed before the restore
- **WHEN** the live block is no longer the block that apply wrote
- **THEN** the restore is refused with its reason and the file is unchanged

### Requirement: The helper is a state in the window, not a sentence in the content

The window MUST show the helper's state in the sidebar footer in every phase,
MUST carry that state as a glyph, a word and a colour together, and MUST offer
the action that resolves it. Helper status MUST NOT appear in the content flow,
and a helper that cannot write MUST NOT prevent reading or editing the store.

#### Scenario: Not registered
- **WHEN** the helper is not registered
- **THEN** the sidebar footer says so and offers to install it

#### Scenario: Awaiting approval
- **WHEN** the helper is registered and awaiting approval
- **THEN** the footer says approval is required and names where it is granted

#### Scenario: Enabled
- **WHEN** the helper is enabled
- **THEN** the footer says writes are available

#### Scenario: Editing while the write is blocked
- **WHEN** the helper is not enabled and a profile is edited and saved
- **THEN** the store holds the edit and the window reports that only the write is blocked

### Requirement: Commands are reachable from the menus and the keyboard

Every action the window offers MUST have a menu item, and the menu bar MUST carry
File, Edit, Profiles, Fragments, Hosts, Window and Help. The window MUST bind:
new profile, new fragment, reload from disk, apply, duplicate, delete, search,
settings, and revealing the applied block.

#### Scenario: New profile
- **WHEN** the new profile command is used
- **THEN** a profile is created in the store and selected

#### Scenario: New fragment
- **WHEN** the new fragment command is used
- **THEN** a fragment is created in the store and selected

#### Scenario: Reload
- **WHEN** the reload command is used
- **THEN** the store and the live file are read again and the window shows what they hold now

#### Scenario: Apply
- **WHEN** the apply command is used while a write is pending
- **THEN** the apply proceeds through its confirmation

#### Scenario: Apply with nothing to write
- **WHEN** the apply command is used while nothing is pending
- **THEN** nothing is written

#### Scenario: Duplicate and delete
- **WHEN** the duplicate or delete command is used
- **THEN** it acts on the selected item

#### Scenario: Search
- **WHEN** the search command is used
- **THEN** the sidebar's search field takes focus

#### Scenario: Settings
- **WHEN** the settings command is used
- **THEN** the settings window opens on the store location and the helper

#### Scenario: Reveal
- **WHEN** the reveal command is used while a block is applied
- **THEN** the hosts file holding the block is revealed

### Requirement: The window searches rather than scrolls

The window MUST offer a search field over the sidebar, MUST match both profiles
and fragments, and MUST keep the selected item editable while a search is
active.

#### Scenario: A search narrows both sections
- **WHEN** text is typed in the search field
- **THEN** the sidebar's sections list only the profiles and fragments matching it

#### Scenario: Clearing the search
- **WHEN** the search text is cleared
- **THEN** the sidebar lists everything the store holds again

### Requirement: The window keeps its shape across launches

The window MUST open at a documented default size that fits three panes, MUST
enforce a content minimum, and MUST restore its size and position across
launches. The window's title MUST name the application, and the selected
profile's name together with its entry and layer counts MUST appear as the
window's subtitle.

#### Scenario: First launch
- **WHEN** the application launches with no restored window state
- **THEN** the window opens at the documented default size

#### Scenario: Restored shape
- **WHEN** the window is resized and the application is launched again
- **THEN** the window opens at the size and position it was left at

#### Scenario: Shrinking past the minimum
- **WHEN** the window is resized smaller than the content minimum
- **THEN** it stops at the minimum rather than clipping its panes

#### Scenario: The subtitle names the selection
- **WHEN** a profile with three layers resolving to nineteen entries is selected
- **THEN** the subtitle names the profile and both counts

### Requirement: Colour carries the brand, and state is never colour alone

The window MUST apply the brand accent to selections, focus rings and the filled
control, and MUST use the brand's two text tiers. Text MUST reach at least 4.5:1
against what it sits on and non-text UI at least 3:1; the muted tier MUST be
reserved for text at 18 points and above, or for non-text detail. Every state
MUST be carried by a glyph, a word and a colour together, and the dark appearance
MUST derive its own values rather than reusing the light ones.

#### Scenario: The filled control
- **WHEN** the primary action is rendered
- **THEN** its label measures at least 4.5:1 against the fill it sits on

#### Scenario: The muted tier
- **WHEN** metadata is rendered below 18 points
- **THEN** it uses a tier that reaches 4.5:1 and not the muted one

#### Scenario: Status
- **WHEN** a write state or helper state is rendered
- **THEN** it carries a glyph and a word as well as a colour

#### Scenario: Dark appearance
- **WHEN** the window renders in dark appearance
- **THEN** each colour is derived for that appearance and every pair still meets its ratio
