# Hazmat

A hosts file manager for Apple Silicon Macs.

Hazmat is an open-source replacement for [Gas Mask](https://github.com/2ndalpha/gasmask), written from scratch for modern Apple Silicon hardware. It does one job: editing `/etc/hosts` and switching between named hosts profiles.

## Why another hosts manager

- **Apple Silicon only.** arm64 native, no Intel or Rosetta code paths.
- **Modern Swift and SwiftUI.** No Objective-C era foundations.
- **Focused surface.** Profile editing, activation, and a menu bar switcher.

## Status

Applying and switching work. The composition and block-rendering core resolves a
profile into a managed block and splices it into `/etc/hosts` byte-preservingly,
and an approved daemon installs or removes that block. A window lists the store's
profiles and reports drift; a menu bar item names the active profile, switches
between profiles, offers a deliberate overwrite for a block no profile owns, and
turns the block off. The active profile is derived from the file's bytes, so an
edit made by another tool is reported as drift rather than overwritten.

Still to come: profile editing, the resolved view, and packaging. The daemon
accepts finished bytes only, and the store stays the source of truth.

## License

MIT
