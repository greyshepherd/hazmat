# Design

## Context

Measured on a release build against the store in use (a 4,698,021-byte fragment stacked by two profiles; `/etc/hosts` 4,551,489 bytes), window closed:

| | Footprint | Live heap | Of which `Data` |
|---|---|---|---|
| This store | 106 MB | 46 MB | 18 MB in 10 buffers |
| Empty store | 63 MB | 26 MB | 4.4 MB (the live file) |

The ten buffers: the fragment's bytes in `StoreCache` (4592 KB), a rendered block per profile stacking it (6144 KB each), the live block copied into the presentation, and the same three for a 367 KB fragment. `vmmap` showed three further 4448 KB regions marked empty: `/etc/hosts` read and freed three times at launch, parked in malloc's large-block cache. `IOSurface` and `CoreAnimation` held 9 MB against 2.5 MB in a fresh process: the closed window's backing.

What the application needs with the window closed: which profile the live block is (bytes compared to bytes), how many entries a profile renders, which fragments a profile stacks, and — for a scheduled refresh that re-applies — which block it is replacing. Every one of these is answered by a digest and a count.

## Goals / Non-Goals

**Goals:**

- With the window closed, the model holds no copy of a fragment, a rendered block or the live block.
- A refresh reads the live file once and leaves no freed large buffer behind.
- Closing the window frees the window.
- Every existing behaviour — applied detection, drift, overwrite, revert, the remote re-apply — is unchanged.

**Non-Goals:**

- The framework floor (SwiftUI, AppKit, Sparkle, Metal: ~45 MB).
- The fragment draft and its baseline, which a close keeps by design so an unsaved edit survives.
- Small-zone fragmentation left by the window's peak.

## Decisions

### D1 — `ByteDigest`: a block's identity

`ByteDigest` in `HazmatCore` wraps a SHA-256 (`CryptoKit`), 32 bytes, `Hashable` and `Sendable`, built from any `DataProtocol` so a slice of the live file is digested without copying. `Replacement.block`, `ProfileRendering.block`, `ActiveProfileState.drifted`, `LiveBlockState.drifted`, `EditorPresentation.liveBlock`, `MenuPresentation.Command.overwriteDrift` and `ApplyRecord.block` carry a `ByteDigest` where they carried `Data`.

`HostsFileApplier.apply` already reads the live file and locates the present block; it compares the present block's digest with the named one and returns the present bytes alongside the outcome, so `ApplyRecord.replaced` — the one block a revert must have bytes for — comes from the apply that replaced it. Revert compares the present block's digest with `change.block`. The spec's "byte-identical" holds: two blocks with one digest are one block for every purpose here.

*Alternative considered*: keep bytes but share storage between the presentation's live block and the cached rendering. Rejected: the scheduled re-apply names the block it replaces with the window closed, so either the bytes stay resident or the name is a digest.

### D2 — The cache keys on the digest; the reading owns the bytes

`StoreCache.FileEntry` keeps `digest` where it kept `bytes`. `StoreReadingCache.file` takes the digest; `StoreReading` computes it as it reads. `FragmentReading` and `ProfileReading` keep the bytes for the reading's life — the selected fragment's text and a parse need them — and the reading is a local of the read that built it. The same-length same-second rewrite the byte comparison was chosen to catch is still caught: the digest is of the bytes, not of metadata.

`FileBytes.read(url)` reads a file for `StoreReading`, `LiveHostsFile` and the applier. A file of 128 KiB or more is read into anonymous pages (`mmap`, `MAP_ANON`) wrapped as `Data(bytesNoCopy:deallocator:)` that unmaps; the kernel takes the pages back the moment the `Data` dies, and malloc's large-block cache never sees them. Below that, `Data(contentsOf:)`. An anonymous mapping rather than mapping the file: a file-backed mapping raises `SIGBUS` when the file is truncated underneath a parse, and an anonymous one has no failure mode a plain read does not.

Cost: one SHA-256 pass per file per read (about 2 ms for 4.7 MB on Apple silicon) where there was a `memcmp`. The earlier design rejected hashing on that basis; it did not weigh 4.6 MB resident per large fragment.

### D3 — A rendering is a summary; the bytes are detail

The `.rendering` derivation is a `BlockSummary` (digest, entry count), kept across a close. The rendered bytes are a `.block` derivation, made only when a detail read asks for the selected profile's block, and released with the parses and compositions; `releaseParses()` becomes `releaseDetail()` to say so. `ResolvedView.rendered` carries the summary; `.composed` carries the composition and the bytes as before. `EditorPresentation.renderedBlock` is `nil` outside a detail read and `entryCount` comes from the summary.

Applied detection compares the live block's digest with each profile's summary. `namingTheMatchedProfile` uses the fresh reading's digest for the matched profile rather than re-composing the profile from disk. Apply renders fresh, as today.

### D4 — One read for the window and the menu

`EditorModel.read` returns an `EditorReading` carrying the presentation and the `ActiveProfileReading`, both derived from one `StoreReading` and one read of the live file through `Activation.match`. `ShellModel.storeRead` and `init` take both from it. `ProfileCatalogue.activation(reading:)` stays for `activate()`, which reads the file again on purpose.

### D5 — The window is the model's `NSWindow`

`ShellWindow` (in `HazmatApp`) makes the window on `show(_:)`: 1080 × 700 by default with `.fullSizeContentView`, as the scene's window had, so the sidebar extends into the title bar; `NSHostingView` over `ShellView` with `sizingOptions = [.minSize]` for the content minimum and `sceneBridgingOptions = [.title, .toolbars]` so the navigation title, the toolbar and the sidebar search reach the window; a frame autosave name for size and position; `isReleasedWhenClosed = false`. On its `willCloseNotification` the controller drops the window; AppKit holds it while the close animates it out and lets it go after, which releases the window, the hosting view and the view tree. `ShellModel.showWindow()` shows it, sets `windowShowing` and reads in full; the close observer clears `windowShowing`, resets the view mode and reads without detail. `paneGeneration`, the `.id` modifiers, `WindowReader`, `windowChanged(_:)` and the `didUpdateNotification` observer go. The `Window` scene goes; `.commands` attaches to the `MenuBarExtra` scene, which is declared first — with no window scene left, SwiftUI opens the first scene it finds at launch, and that must not be `Settings`; `StatusMenu` and `ShellCommands` call `showWindow()`; `Launch`, an `NSApplicationDelegateAdaptor`, shows the window at launch as the scene did and on a Dock reopen.

*Alternative considered*: keep the scene and clear the closed window's content view. Rejected: the scene owns the window and rebuilds what it needs; only owning the window lets a close free it.

### D6 — The bundle launches the application in malloc's space-efficient mode

Freeing the window's tree is not the same as the process shrinking: malloc keeps what it freed. Measured after a close, the composition, the entry lines and the text storage of the 169k-entry block sat in thirteen empty `MALLOC_LARGE` regions of 3–13 MB, 94–107 MB in all, and stayed there; `malloc_zone_pressure_relief`, tried on an 80 MB free in isolation, returned none of it, confirming what the closed-window-memory change had found. With `MallocSpaceEfficient=1` in the process environment, a freed large block goes back to the kernel at once and the small zones return their free pages: open 83 MB and closed 42 MB against 177–188 and 82–186. The bundle declares it under `LSEnvironment`, which LaunchServices applies to every launch of the bundle, and the verifier refuses a bundle without it. The cost is a page fault per page of each large allocation, milliseconds for a composition, in exchange for a process that is the size of what it holds.

*Alternative considered*: `MallocLargeCache=0` alone. It returns the large blocks but not the small zones' pages (closed 91 MB); the broader mode is the one Apple names for processes that should stay small.

## Risks / Trade-offs

- [The toolbar, the search field, the sheets or the confirmation dialogs render differently under a hosting view than under the scene] → checked by hand in the built application; `sceneBridgingOptions` is what SwiftUI provides for exactly this.
- [A digest collision] → SHA-256; not a practical concern.
- [A file grows between its size being read and its bytes] → `FileBytes` reads until end of file and falls back to `Data(contentsOf:)` when the file is larger than it was.
- [The first launch after this opens at the default size] → accepted; the frame is saved from then on.
- [A launch that bypasses LaunchServices — the executable run from a shell — has no `LSEnvironment`] → it runs as before this change; every ordinary launch (Finder, Dock, `open`, a login item, Sparkle's relaunch) goes through LaunchServices.
