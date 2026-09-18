# Design

## Context

The menu bar and the window render one value, built from the editor's read by
`CommandPresentation.menuBar`. Every action the window can perform has an item
there, listed even when it cannot act in the current state and reported disabled
so nothing unusable appears to work. That rule is what made the two item-type
menus and the two host-file items look justified: the actions exist, so they were
given items.

They are the wrong items. A menu bar command list is read apart from the
selection it acts on, so the Profiles and Fragments menus spent their life
disabled whenever the sidebar was not holding the selection they needed, and
nothing in the menu bar said which profile "Rename Profile…" would rename. The
sidebar row already carries the item, its state, and its context menu. The same
applies to the restore and the drift overwrite: both act on what the window is
showing, and both are already offered next to what they act on — the status row
beside the write state, the status item's menu beside the drift it read.

## Goals / Non-Goals

**Goals:**
- Every command remains reachable, on the surface that shows what it acts on.
- No menu-bar item acts on something the menu bar cannot name.

**Non-Goals:**
- Changing the status item's menu, the window's panes, or what any command does.
- Preserving the removed keystrokes by another route; the actions stay, the
  bindings do not.

## Decisions

**The menu bar keeps what does not depend on a selection.** File, Edit, Hosts,
Window and Help hold the commands whose subject is the application, the store, or
the hosts file as a whole: new profile, new fragment, save, search, apply, reveal,
reload, remove the block, the store commands, the helper commands, the sidebar
toggle and the help sheet. Removing the Profiles and Fragments menus takes away
nothing that cannot be done from the row it applies to.

**The restore stays in the status row, and the drift overwrite in the status
item's menu.** The restore is offered only after an apply this session performed,
which is state the window shows; the drift overwrite is offered only for a block
that matches no profile, which the reading names and the status item's menu
presents as its own deliberate item. Both are the surface that already decides
whether the action can act. The Hosts menu listed them disabled in every other
state.

**The presentation loses the revert flag with the item.** `canRevert` reached
`menuBar` only to enable that one item. The window still derives the row's
restore from the same session record, so the flag stays where it is read.

## Risks / Trade-offs

- The duplicate and delete keystrokes go with their menus → the actions stay on
  the row's context menu, which shows no keystroke; a user who wants the bindings
  back says so, and they can be moved to the File menu rather than restored as
  item-type menus.
- The restore is no longer reachable with the window closed → it was already
  offered as a command that needed the window, so the removed item opened the
  window before asking; the window now has to be open to see the offer.
- A value-level test can no longer assert that every action has a menu item → the
  test asserts what the menu bar carries and what it does not, and the surfaces
  that carry the removed commands are covered where they live.
