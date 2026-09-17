# Hazmat

A hosts file manager for Apple Silicon Macs.

Hazmat is an open-source replacement for [Gas Mask](https://github.com/2ndalpha/gasmask), written from scratch for modern Apple Silicon hardware. It does one job: editing `/etc/hosts` and switching between named hosts profiles.

## Why another hosts manager

- **Apple Silicon only.** arm64 native, no Intel or Rosetta code paths.
- **Modern Swift and SwiftUI.** No Objective-C era foundations.
- **Focused surface.** Profile editing, activation, and a menu bar switcher.

## Status

Applying, switching, and editing work. The composition and block-rendering core
resolves a profile into a managed block and splices it into `/etc/hosts`
byte-preservingly, and an approved daemon installs or removes that block. A
window edits the store's profiles and fragments, stacks a profile's layers, and
shows what it resolves to; a menu bar item names the active profile, switches
between profiles, offers a deliberate overwrite for a block no profile owns, and
turns the block off. The active profile is derived from the file's bytes, so an
edit made by another tool is reported as drift rather than overwritten. Editing
the store needs no privilege, and it stays inside the store.

Still to come: packaging, signing, and the update channel. The daemon accepts
finished bytes only, and the store stays the source of truth.

## License

MIT
