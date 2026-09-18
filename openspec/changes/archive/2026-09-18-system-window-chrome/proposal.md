# Proposal

## Why

The window reads as foreign next to every other macOS window: it paints
hand-picked surfaces and text tiers over the system's own, ignores the accent the
user chose in System Settings, and carries a palette that has to be measured
against a contrast threshold by hand whenever it changes. Two chrome defects come
with it: a command that asks the window for something opens a second window when
one is already open — which macOS presents as a tab — and the toolbar draws a
sidebar toggle beside the one the split view supplies. And the window renders as
an empty frame in the states a store starts in: the split view takes its height
from the content it measures, so a first run and a profile with no layers push
every pane outside the window.

## What Changes

- The window takes its colours from the system: semantic surfaces and separators,
  the system's two text tiers, and the user's accent for selections, focus rings
  and the filled control. The code-defined tokens, the environment value that
  carried them, and the hand-measured contrast test go with them.
- A state stays a glyph, a word and a colour together; the colour is now the
  system's own status colour.
- The window becomes a single instance. A command that needs the window brings
  the open one forward, and nothing produces a second window or a system tab.
- The toolbar stops drawing its own sidebar toggle and leaves the one the split
  view supplies. The Window menu's Toggle Sidebar command stays, holding the same
  state as that toggle.
- The panes take their height from the window rather than from their content, so
  the panes stay inside the frame in the states a store starts in.
- **BREAKING**: the palette value type, its light and dark derivations and the
  environment value that carried them are removed.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `app-window`: the colour requirement becomes the system's surfaces, text tiers
  and the user's accent, and three requirements are added — one window per run, no
  control drawn twice, and panes that stay inside the window's frame.

## Impact

- `Sources/HazmatApp`: every view stops reading an injected palette and uses
  system styles instead; the entry point declares a single window; the height
  modifiers that let a text size the split view are removed.
- `Sources/HazmatAppSupport`: the palette tokens, their appearance derivations and
  the hex and contrast helpers are removed; the status-tone vocabulary stays.
- Tests: the palette contrast test is deleted, and the isolation test that
  requires the entry point to declare a window group is corrected to require one
  window.
