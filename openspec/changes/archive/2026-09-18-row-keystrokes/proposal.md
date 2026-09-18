# Proposal

## Why

The two commands that act on a sidebar row carry no keystroke any more: ⌘D and
⌘⌫ went with the Profiles and Fragments menus, and a row's context menu shows no
keystroke of its own. A keystroke does not need a menu bar item — only a key
equivalent the window answers — so the binding can come back where the row is,
without the menus that made the menu bar act on a selection it could not show.

One of the two needs care rather than a plain binding. ⌘⌫ is the text system's
own "delete to the start of the line", so a window that answers it takes it away
from every text field in the application, which it did while the menu item
existed: pressing it to clear a line in a fragment deleted the selected row
instead. Deleting a row is unconfirmed and removes the file, so this is the one
keystroke that has to be given back while someone is typing.

## What Changes

- The window answers ⌘D and ⌘⌫ without a menu bar item: ⌘D asks for the
  duplicate's name as the row's context menu does, and ⌘⌫ deletes the selected
  profile or fragment.
- ⌘⌫ is given back to a focused text view, which keeps its own binding: with a
  text field or the fragment editor focused, the keystroke deletes to the start
  of the line and no store item is deleted.
- The keystrokes act only while the window that shows the selection is the key
  one. A sheet, the settings window, and the store chooser are each key at times,
  and a keystroke answered there would act on a row none of them shows.
- The keystrokes are values in app support, so which keystroke asks for which
  action, and which one yields, is decided and tested without a window.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `app-window`: the command requirement's binding list gains duplicate and
  delete, and gains the rules a window's own keystroke obeys — no menu bar item,
  only while the window showing the item is key, and given back to a focused text
  view when the text system binds it.

## Impact

- `Sources/HazmatAppSupport`: the keystrokes and their rule are a new value; the
  menu bar's value is unchanged.
- `Sources/HazmatApp`: the shell answers the keystrokes through a local event
  monitor, which is what lets one be passed on rather than taken; the shell view
  tells the model which window it is in.
- Tests: the keystroke-to-action mapping and the yield rule are covered as
  values; the menu-bar checks are unchanged.
- Nothing changes in the store, the block format, the apply path, the status
  item's menu, or the window's panes.
