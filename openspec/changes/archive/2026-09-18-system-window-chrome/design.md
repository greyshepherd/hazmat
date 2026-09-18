# Design

## Context

The window's colours are code-defined tokens carried to every view through a
`\.brand` environment value, and a test measures their WCAG ratios. The values
are sRGB triples, so the window ignores both the appearance and the accent the
user chose in System Settings, and every surface the system would draw for a
split view is painted over. The entry point declares a window group, so the
command path's `openWindow(id:)` — used whenever a command needs the window —
creates a second window, which macOS shows as a tab. The toolbar draws a sidebar
toggle as well as the one the split view supplies.

## Goals / Non-Goals

**Goals:**

- The window's appearance follows the system: surfaces, text tiers and status
  colours, with the user's accent on selections, focus rings and the filled
  control.
- One window per run, whatever a command asks for.
- One sidebar toggle, with the Window menu's command and the title bar's control
  reporting the same state.

**Non-Goals:**

- No new theme, no token layer that re-derives the system's colours, and no
  appearance-dependent view code.
- No change to what the window offers, the phases it derives, or the write path.
- No custom window chrome, titlebar accessory or toolbar styling beyond removing
  the duplicate control.

## Decisions

**The system's semantic colours replace the tokens, and the app keeps only the
state vocabulary.** `Color.primary`/`.secondary`/`.tertiary`, the system
materials for bars and sidebars, and `Divider()`/separator strokes cover what the
20 tokens did. `StatusTone` stays in app support because it names a state, not a
colour; the window maps it to the system's status colours in one place, so views
still decide nothing. The palette value type, its light and dark derivations, the
hex and luminance helpers and the contrast test go, because the ratios they
measured are now the system's contract. Alternative considered: keep the tokens
and re-derive them per appearance from system colours — rejected as a second
palette to maintain that still overrides the user's accent.

**A single-window scene replaces the window group.** `Window` is one instance by
definition, so `openWindow(id:)` brings the existing window forward instead of
creating another; nothing has to dedupe. The open-then-perform delay in the
command path stays, because the scene's activation is asynchronous. Alternative
considered: keep `WindowGroup`, suppress system tabbing and replace the New Window
command — rejected because it leaves the second-window path in place for every
other command that needs the window.

**The split view's toggle is the only toggle.** The toolbar item goes; the
`columnVisibility` binding the split view drives and the Window menu's command
both write the shell model's sidebar flag, so they cannot disagree. Alternative
considered: keep the window's own button and hide the system one — rejected
because the system control is the one that matches every other macOS window and
carries its own accessibility and keyboard behaviour.

**A pane's height comes from the window, not from its content.** A text carrying
`fixedSize(horizontal: false, vertical: true)` reports the height of the width it
is given, and the split view measures its columns at a width of zero: a
103-character paragraph then measured one character per line, about 1440 points,
which grew the split group to 4922 points in the tightest state and left every
pane outside the window. The modifier is gone wherever the window used it; the
text wraps in the width it is given and the panes take the window's height.
Alternative considered: keep the modifier and pin a minimum width on the pane
content — rejected as treating the symptom, since the width the pane is measured
at is not the pane's to decide.

**The window view file is renamed.** The file that carried the palette bridge and
the shared status views is named for the palette it no longer holds, so it becomes
`WindowViews.swift` and the isolation test's scene list follows it.

## Risks / Trade-offs

- [A command's action fires before a reopened window is ready] → Keep the
  existing delay before performing the action, and verify with the window closed.
- [Removing the palette hides a real regression in text contrast] → The window now
  uses only the system's tiers; the modes that mattered (dark, the filled control,
  a dimmed tier below 18 points) are verified on screen instead of by ratio.
- [Deleting the palette leaves dangling references] → The compiler and the
  isolation tests catch them; the test suite runs before the bundle build.
- [The renamed view file falls out of the isolation rules] → Update the scene list
  in the isolation test in the same change, so the rules keep covering it.
- [A text that used the height modifier now truncates where it was kept whole] →
  The panes are top-aligned in a window-sized column, so each text takes its
  natural height; the first-run, empty-store, fragment and populated-profile
  states were measured on the running bundle.
