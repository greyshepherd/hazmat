# Changelog

All notable changes to Hazmat are listed here, newest first. Each release
carries a higher build number than the one before it; published versions are
never rewritten. A published version's section is what its release page carries,
so it is not rewritten either — the next version says what changed.

## 1.1.0 — 2026-09-19

Fragment renames that carry their references, a privileged side that checks the
sender of every message, and a window that acts on the row a menu names.

- A fragment rename rewrites every profile that stacked it, so composition keeps
  resolving and a block that was live stays the applied one rather than becoming
  drift.
- The daemon checks the audit token of each message's sender against the code
  requirement, rather than once when the connection was accepted, and refuses a
  request whose bytes outside the block differ from the live file. A client that
  satisfies the requirement can no longer rewrite the rest of `/etc/hosts`.
- The helper is asked off the main thread: the first window no longer waits on a
  presence check, and saving a fragment or changing a profile's layers no longer
  freezes the window when the helper does not answer. An apply asked for while
  one is in flight is dropped rather than raced.
- A row's context menu acts on the row it was opened on, and deleting a profile
  or a fragment asks first, naming what goes with the file.
- The menu bar carries File, Edit, Hosts, Window and Help. ⌘D duplicates the
  selected row and ⌘⌫ deletes it, and ⌘⌫ still reaches a focused text view.
- The layers pane opens minimal, and the divider sizes it against a resolved
  block that keeps a width it stays readable at.
- The release page carries the changelog's section for the version it publishes,
  so the page and the changelog are one text.

## 1.0.1 — 2026-09-18

Release tooling hardening; the app itself is unchanged from 1.0.0.

- A half-finished publish can be run again: feed entries are written as whole
  lines and the feed's next position is found without a fragile text search.
- The disk image is signed and notarized like the app, and each artifact is
  assessed by its own kind.

## 1.0.0 — 2026-09-18

Initial release.

- Profiles composed from shared fragments; layers apply in order and a later
  layer wins a conflict.
- The resolved block splices into `/etc/hosts` through an approved helper,
  byte-preservingly: the rest of the file is left exactly as it was.
- Applying is a review step with a confirmation, a kept previous block to
  revert to, and deliberate confirmation before overwriting drift.
- Menu bar switching between profiles, with a deliberate overwrite for a block
  no profile owns and a switch to turn the block off.
- Signed, notarized builds with in-app updates.
