# Spec Delta

## MODIFIED Requirements

### Requirement: Commands are reachable from the menus and the keyboard

Every action the window offers MUST be reachable from the surface that acts on it
and shows its subject: the menu bar, the item's own row, the pane or status row
it belongs to, or the status item's menu. The menu bar MUST carry File, Edit,
Hosts, Window and Help, and MUST NOT carry a menu for a store item type. The
window MUST bind: new profile, new fragment, reload from disk, apply, search,
settings, and revealing the applied block. Renaming, duplicating and deleting a
profile or a fragment MUST be offered on that item's row. Restoring the block an
apply replaced MUST be offered beside the write state, and overwriting a block
that matches no profile MUST be offered for the drifted block the reading found.

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
- **WHEN** duplicate or delete is chosen for a selected profile or fragment
- **THEN** it acts on that item

#### Scenario: Search
- **WHEN** the search command is used
- **THEN** the sidebar's search field takes focus

#### Scenario: Settings
- **WHEN** the settings command is used
- **THEN** the settings window opens on the store location and the helper

#### Scenario: Reveal
- **WHEN** the reveal command is used while a block is applied
- **THEN** the hosts file holding the block is revealed

#### Scenario: The menu bar names what it acts on
- **WHEN** the menu bar is shown
- **THEN** it carries File, Edit, Hosts, Window and Help, and neither a Profiles menu nor a Fragments menu

#### Scenario: The restore is offered where the write state is
- **WHEN** the window offers restoring the block an apply this session replaced
- **THEN** the offer is beside the write state, and the menu bar carries no item that restores a block

#### Scenario: The overwrite is offered for the block that was read
- **WHEN** the live block matches no profile and the overwrite is offered
- **THEN** it is offered for that block from the status item's menu, and the menu bar carries no item that overwrites a block
