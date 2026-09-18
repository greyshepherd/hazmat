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
byte-preservingly, and an approved daemon installs or removes that block. The
window shows three panes at once — the store's profiles and fragments, the
selected item, and the block it resolves to — and offers one next step whatever
state it is in: no store, no profiles, a profile with no layers, changes pending,
in sync, or a blocked write. Applying is a review step: a confirmation names the
file and the entry count, the block it replaced is kept so the change can be
reverted, and overwriting drift or removing the block is confirmed as
destructive. The store's location is choosable in Settings, with the environment
override still authoritative. A menu bar item names the active profile, switches
between profiles, offers a deliberate overwrite for a block no profile owns, and
turns the block off. The active profile is derived from the file's bytes, so an
edit made by another tool is reported as drift rather than overwritten. Editing
the store needs no privilege, and it stays inside the store.

A bundle is assembled from one configuration: the app icon and the status item's
mark come from the exported brand set, the version and the feed come from one
file, and the update framework is embedded and signed with the rest. Still to
come: a notarized release, and a published feed to point the update channel at.
The daemon accepts finished bytes only, and the store stays the source of truth.

## Building

```
Scripts/assemble-bundle.sh debug     # signed ad-hoc, declares no feed
Scripts/assemble-bundle.sh release   # signed with a Developer ID, declares the feed
open build/Hazmat.app
```

`Scripts/verify-bundle.sh build/Hazmat.app` reports what a bundle carries, what it
reports, what it loads, and how it is signed. `release/README.md` describes the
values a release reads.

## License

MIT
