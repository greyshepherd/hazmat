# Changelog

All notable changes to Hazmat are listed here, newest first. Each release
carries a higher build number than the one before it; published versions are
never rewritten. A published version's section is what its release page carries,
so it is not rewritten either — the next version says what changed.

## 1.3.0 — 2026-09-21

- A fragment can be fetched from a URL on its own interval and refreshed over
  HTTPS, keeping the previous text when a fetch fails and applying a changed
  block when the live file still matches the profile's rendering, or reporting
  drift otherwise. (#2)
- A profile or fragment name can hold a space, so a name like `Local Dev` is
  created, listed and referenced. (#1)
- Large hosts files cost far less memory: closing the window releases it and its
  view tree, the application holds digests and counts rather than file bytes, and
  the resolved block builds only the rows on screen.

## 1.2.0 — 2026-09-20

A store of a hundred thousand entries is usable, and the resolved block fills the
pane it is shown in.

- The size bound is 16 MiB rather than 1 MiB, parsing and block location run over
  bytes, and a read parses each fragment once rather than once per row, layer and
  profile. A 100,000-entry fragment now applies.
- The store is read every time it is asked; only a derivation whose bytes come
  back unchanged is reused.
- Reads run off the main actor, so the window and the menu stay responsive, a slow
  read cannot replace a later one, and a read never overwrites a draft being
  edited.
- The block's text view and the fragment editor lay out only what is visible, and
  the displaced list is lazy.
- A fragment whose lines end in `\r\n` is read line by line rather than as one
  malformed entry.
- The resolved block takes the height left in the pane rather than sitting at its
  minimum with the window empty below it.
- Publish hashes the archive the release host serves against the one built here,
  and a script's `--help` prints its whole header.

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
