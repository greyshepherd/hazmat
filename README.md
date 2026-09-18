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
override still authoritative. A menu bar item carries the mark alone, with the
state in its accessibility label and its menu: the menu marks the active profile,
switches between profiles, offers a deliberate overwrite for a block no profile
owns, turns the block off, and opens or quits the application. Closing the window
leaves the application in the menu bar alone. The active profile is derived from
the file's bytes, so an edit made by another tool is reported as drift rather
than overwritten. Editing the store needs no privilege, and it stays inside the
store.

The daemon accepts finished bytes only, and the store stays the source of truth.
It requires the team the running binary was signed with, so a distribution build
cannot accept an ad-hoc client, and it stops after a period with no open
connection so a replaced build cannot keep answering. The release path is
complete: one assembler builds the development and release bundles from one
configuration, `Scripts/release.sh` signs, notarizes, staples, and assesses the
artifact, and `Scripts/publish.sh` uploads it and publishes the feed entry naming
it. What is left is the one-time setup a first release needs, and the upgrade it
is accepted by.

## Building

```
Scripts/assemble-bundle.sh debug     # signed ad-hoc, declares no feed
Scripts/assemble-bundle.sh release   # signed with a Developer ID, declares the feed
open build/Hazmat.app
```

`Scripts/verify-bundle.sh build/Hazmat.app` reports what a bundle carries, what it
reports, what it loads, and how it is signed.

## Releasing

```
Scripts/release.sh    # assemble, sign, notarize, staple, and assess
Scripts/publish.sh --artifact build/release/Hazmat-<version>.dmg
```

`release/README.md` describes the configuration both steps read, the credentials
they take from the environment, and the one-time setup a first release needs.
Installed copies check `https://greyshepherd.github.io/hazmat/appcast.xml` for a
newer build.

## License

MIT
