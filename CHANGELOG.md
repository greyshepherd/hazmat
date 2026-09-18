# Changelog

All notable changes to Hazmat are listed here, newest first. Each release
carries a higher build number than the one before it; published versions are
never rewritten.

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
