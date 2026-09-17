# Proposal

## Why

Hazmat can switch between profiles but not author them. The store's layout lives
only in code, so a fragment or a profile has to be created and edited by hand in
a text editor, and nothing in the application shows what a profile resolves to.
Editing is the last capability the README names that is not built, and
composition already produces everything a resolved view needs.

## What Changes

- Fix the store's location and layout as a contract: a root, `fragments/`, and
  `profiles/`, one file per name, with the environment override kept for tests
  and development bundles.
- Add authoring over that store: create, rename, duplicate, and delete a profile
  or a fragment; save fragment text; add, remove, and reorder a profile's layers.
- Make store writes unprivileged, atomic, and name-validated, so a refused name
  cannot leave the store directory and a failed write leaves the previous text.
- Turn the window into the editor: the store's profiles and fragments, the
  selected fragment's text, the profile's layer stack, and the resolved entry set
  with the fragment behind every entry and every problem.
- Re-apply an edit of the applied profile only over the block Hazmat itself
  wrote: the live block must still be byte-identical to what that profile
  rendered before the edit. Any other block is left alone and reported as drift.
- **BREAKING** (client-side API): the apply path's `overwriteDrift` flag becomes
  the block the caller expects to replace, so a deliberate overwrite names what
  it overwrites rather than asserting that an overwrite is intended.

## Capabilities

### New Capabilities

- `profile-store`: where the store lives, how it is laid out, and what an
  authoring operation guarantees - name validation, atomic replacement, no
  privilege, and a live hosts file it never touches.
- `profile-editor`: the window that edits the store and explains the result -
  profile and fragment authoring, the layer stack, the resolved view, and the
  re-apply rule for the profile that is currently applied.

### Modified Capabilities

- `hosts-apply`: a deliberate overwrite names the block it expects to replace,
  and is refused when the live block differs from that expectation.

## Impact

- `HazmatCore` gains a Foundation-only store writer beside the existing
  directory reader, and keeps importing nothing outside Foundation.
- The apply path's overwrite contract changes, so both the window and the menu
  bar pass the block they expect instead of a flag.
- `HazmatApp` gains the editor scene; its decisions stay in app support, as the
  menu bar's already do.
- The shell's isolation guard changes: the test that forbids an editor and a
  resolved view is replaced by a guard for the editor scene's own thinness and by
  a guard for what is still absent, which is packaging.
- No new privileged surface: no XPC method, no daemon change, no new reason for
  the helper to be involved.
