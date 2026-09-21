# Proposal

## Why

With the window closed a release build sits at about 100 MB on a store holding one 4.7 MB fragment, and 63 MB on an empty store. Measured with `footprint`, `heap` and `vmmap`: 18 MB of it is `Data` the model holds — the fragment's bytes in the cache, one rendered block per profile that stacks it, and a copy of the live block in the presentation; 13 MB is freed 4.4 MB buffers malloc keeps after `/etc/hosts` was read four times at launch (twice per refresh: once for the window's presentation, once for the menu's activation); and about 7 MB is the closed window's layer tree and backing surfaces, which a SwiftUI `Window` scene keeps after the window is ordered out. The rest is the framework floor.

None of the bytes are needed with the window closed. What the menu and the schedule ask is whether the live block *is* a profile's rendering and how many entries it holds, which a digest and a count answer.

## What Changes

- A block's identity is a digest of its bytes, not the bytes: what an apply names as the block it replaces, what a profile's rendering is compared against, what drift carries, and what a revert checks. The bytes a revert writes back come from the apply that replaced them, read by the apply itself.
- The cache keys a file on the digest of its bytes rather than a copy of them, so the store's bytes live only for the read that made them. A file above 128 KiB is read into pages the kernel takes back when the reading lets them go, rather than into malloc.
- A profile's rendering is held across reads as a digest and an entry count. The rendered bytes are derived only for the window's selected profile and let go with the parses when the window closes.
- One read serves the window and the menu: the editor's read derives the activation from the same live bytes and renders, so a refresh reads `/etc/hosts` once.
- The window is an `NSWindow` the shell model shows and lets go of: closing it releases the window, the hosting view and the whole view tree, rather than giving the panes a new identity inside a scene that keeps the window.
- The bundle launches the application in malloc's space-efficient mode, so what a close frees goes back to the system rather than into malloc's large-block cache, which was measured not to drain by itself or on request.

Nothing in what the window shows, offers or writes changes. Measured on the same store after the change: window open 82 MB, window closed 38 MB.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `app-window`: closing the window releases the window; the application keeps digests and counts, not bytes, while it lives in the menu bar.
- `profile-editor`: derived work is reused between reads while the digest of the bytes read is unchanged.
- `app-bundle`: the bundle launches the application in malloc's space-efficient mode, and the verifier checks that it does.

## Impact

- `Sources/HazmatCore`: `ByteDigest` and `FileBytes` (new); `Activation`, `HostsFileApplier`, `StoreReading`, `StoreReadingCache`, `LiveFile`.
- `Sources/HazmatAppSupport`: `StoreCache`, `EditorModel`, `EditorPresentation`, `ActiveProfileReading`, `MenuPresentation`, `StoreSession`, `ProfileCatalogue`.
- `Sources/HazmatApp`: `ShellWindow` and `Launch` (new), `HazmatApp`, `ShellModel`, `ShellView`, `ShellCommands`, `StatusMenu`, `WindowViews`.
- `Scripts/assemble-bundle.sh` and `Scripts/verify-bundle.sh`: the launch environment.
- Tests across `HazmatCoreTests`, `HazmatAppSupportTests`, `HazmatAppTests` and `HazmatPackagingTests`.
- No new dependencies (`CryptoKit` is the system's). No change to the store, the block, the protocol or the helper. The frame SwiftUI saved for the window is under its own key, so the first launch after this opens at the default size once.
