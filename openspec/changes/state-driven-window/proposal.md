# Proposal

## Why

The window renders every control in every phase, so a first run reads as a broken
install rather than a first step: eleven buttons share one visual weight, the
lists stand empty with no entry point, and the block that is about to be written
to `/etc/hosts` renders as an unlabelled bar. Meanwhile the model the app is
built on — profiles of ordered layers resolving into one managed block — is not
visible anywhere on screen. Applying, switching and editing all work now, so the
window is the last surface that does not reflect what the app can do.

## What Changes

- The window becomes three panes: a sidebar listing the store's profiles and
  fragments with selection and the helper's status in its footer, a content pane
  editing the selected fragment or profile, and a detail pane showing the block
  the selected profile resolves to.
- The window becomes phase-driven. No store, no profiles, a profile with no
  layers, changes pending, in sync, and helper missing each get their own content
  and exactly one primary action; the write action exists only when there is
  something to write.
- A write bar reports `In sync`, `N changes pending`, or `Blocked`, derived from
  the live file's block and the helper's state.
- Applying is a review step: a confirmation names the file and the affected entry
  count, and the block that was replaced is retained so the apply can be reverted
  from the same window. A revert is refused when the file changed since.
- One accent fill sets the brand on the window; the window uses the brand's two
  AA text tiers, and every state carries a glyph, a word and a colour rather than
  colour alone.
- Empty states become `ContentUnavailableView` with the action that fills them,
  and placeholder-only fields become labelled fields.
- The window gains a toolbar, menus (File, Edit, Profiles, Fragments, Hosts,
  Window, Help) and shortcuts: ⌘N, ⇧⌘N, ⌘R, ⌘⏎, ⌘D, ⌘⌫, ⌘F, ⌘,, plus search over
  profiles and fragments and drag reordering of a profile's layers.
- The store's location becomes choosable in a Settings scene, with the
  environment override still honoured, and an explicit *Create Store* action
  replaces today's implicit creation.
- Overwriting drift and removing the block take the destructive role, name the
  consequence before writing, and are never one click from the primary flow.
- The window opens at 1080×700 with a content minimum and restores its size and
  position; the helper gains an install sheet reachable from onboarding and from
  the sidebar footer.
- Layer rows keep drag-to-reorder, per-layer entry counts, and remove. No
  switched-off layer is introduced: a layer that is not in the stack is the only
  off state, so the window never shows a state the profile file cannot hold.

## Capabilities

### New Capabilities

- `app-window`: the window surface — three-pane structure and selection, the
  phase model and its one primary action per phase, the write bar, the apply
  review step and revert, helper status and the install sheet, menus and
  shortcuts, search, window sizing and restoration, and the appearance and
  contrast rules the window renders with.

### Modified Capabilities

- `profile-editor`: store editing is restructured around the panes — selection
  affordances, empty states that offer the next action, per-layer detail, the
  profiles a selected fragment is used by, the resolved view as text or as a
  table, and search.
- `profile-store`: the store's location becomes choosable in the app, resolved as
  the environment override, then the chosen location, then the default; the store
  can be created explicitly before any profile exists; changing the location
  re-reads the store rather than merging it, and the choice is remembered.
- `hosts-apply`: an apply retains the block it replaced so the change can be
  reverted, and a revert is refused with a reason when the file changed since the
  apply.

## Impact

- `HazmatApp`: the shell view becomes a `NavigationSplitView`; new window
  surfaces for onboarding, the write bar, the helper sheet and settings; the app
  gains a Settings scene and menu commands.
- `HazmatAppSupport`: the editor presentation gains the hosts file path, entry
  and layer counts, per-layer counts, a fragment's using profiles, search text
  and a write state; the shell model gains store creation, a
  re-pointable store root, and revert.
- `HazmatCore`: store location resolution (chosen, environment, default) and
  explicit store creation. Composition, block rendering and splicing are
  unchanged.
- `HazmatPrivileged` and the XPC interface are unchanged: still bytes, still two
  methods.
- Brand assets (app icon, menu-bar mark, accent and text tiers) enter the bundle;
  the development bundle script copies them.
- Tests: the shell's helper-status assertions and the scene isolation rules
  change with the view, and write state, revert, using profiles and location
  resolution need app-support tests.
