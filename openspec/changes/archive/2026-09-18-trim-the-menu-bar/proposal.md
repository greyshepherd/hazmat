# Proposal

## Why

The menu bar offers two ways to reach the same store items and two ways to reach
the same host-file actions. The Profiles and Fragments menus act on the sidebar's
selection, which the menu bar cannot show: their items are enabled or disabled by
a choice made in another surface, and the same commands already sit on the row's
context menu, where the item they act on is visible. The Hosts menu repeats the
restore the status row offers beside the write state, and the drifted-block
overwrite the status item's menu offers for the block its reading named. Each
duplicate path is one more place to look for an action and one more item that can
be offered where it cannot act.

## What Changes

- The menu bar drops the Profiles and Fragments menus. Renaming, duplicating and
  deleting a profile or a fragment stay on the sidebar row's context menu, which
  is where the selection they act on is shown.
- The Hosts menu drops "Revert the Last Apply" and "Overwrite the Drifted
  Block…". The restore stays beside the write state in the window, offered after
  an apply this session performed, and the deliberate overwrite stays in the
  status item's menu for the drifted block that reading named.
- The menu bar carries File, Edit, Hosts, Window and Help.
- **BREAKING**: the duplicate and delete keystrokes go with the menus they were
  bound in; both actions remain on the row's context menu.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `app-window`: the command requirement becomes "every action is offered where it
  acts" instead of "every action has a menu item": the menu bar carries File,
  Edit, Hosts, Window and Help with no menu for an item type, the row's context
  menu carries renaming, duplicating and deleting, the status row carries the
  restore, and the status item's menu carries the drifted-block overwrite.

## Impact

- `Sources/HazmatAppSupport`: `CommandPresentation` loses two menus and two
  items, and the revert flag no longer reaches the menu bar.
- `Sources/HazmatApp`: `ShellCommands` loses the two `CommandMenu` declarations.
- Tests: the menu-bar menu set, item set and shortcut list are corrected; the
  checks over the restore and the drift overwrite move to the surfaces that keep
  them.
- Nothing changes in the store, the block format, the apply path, or the status
  item's own menu.
