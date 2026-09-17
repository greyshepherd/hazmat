# Hazmat

A hosts file manager for Apple Silicon Macs.

Hazmat is an open-source replacement for [Gas Mask](https://github.com/2ndalpha/gasmask), written from scratch for modern Apple Silicon hardware. It does one job: editing `/etc/hosts` and switching between named hosts profiles.

## Why another hosts manager

- **Apple Silicon only.** arm64 native, no Intel or Rosetta code paths.
- **Modern Swift and SwiftUI.** No Objective-C era foundations.
- **Focused surface.** Profile editing, activation, and a menu bar switcher.

## Status

Early, but applying works. The composition and block-rendering core resolves a
profile into a managed block and splices it into `/etc/hosts` byte-preservingly,
and an approved daemon installs or removes that block. A minimal window lists the
store's profiles, reports drift, and offers apply, overwrite, and remove.

Still to come: profile editing, the resolved view, the menu bar switcher, and
packaging. The daemon accepts finished bytes only, and the store stays the source
of truth.

## License

MIT
