# Tasks

## 1. The menu bar

- [x] 1.1 Remove the Profiles and Fragments menus from the command presentation and the scene that declares them; verify the menu bar carries File, Edit, Hosts, Window and Help and no menu for a store item type
- [x] 1.2 Leave renaming, duplicating and deleting on the sidebar row's context menu; verify each is offered for a selected profile and a selected fragment and appears in no menu bar
- [x] 1.3 Correct the menu-bar tests: the menu set, the item set, the bound shortcuts, and the selection-dependent checks the removed items carried

## 2. The Hosts menu

- [x] 2.1 Remove the restore and the drift overwrite from the Hosts menu; verify the Hosts menu's items, that the status row still offers the restore beside the write state, and that the status item's menu still offers the overwrite for the block its reading found
- [x] 2.2 Drop the flag that only the removed item used from the presentation and its callers; verify the value builds without it and the window's restore is unchanged

## 3. Verification

- [x] 3.1 Run the full test suite and verify it passes
