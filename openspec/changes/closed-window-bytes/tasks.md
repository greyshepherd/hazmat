# Tasks

## 1. A block's identity is a digest

- [x] 1.1 `ByteDigest` in HazmatCore with a test: equal for equal bytes, different for bytes of the same length that differ, the same for a `Data` and a slice holding the same bytes.
- [x] 1.2 `Replacement.block`, `ProfileRendering.block`, `ActiveProfileState.drifted` and `Activation.match` carry a digest; `HostsFileApplier.apply` compares digests and returns the replaced bytes; `ApplyRecord.block` is a digest and `revert` checks it. Tests in `HostsFileApplierTests`, `ActivationTests` and `StoreSessionTests` adapted, with one new case: an apply that names a digest replaces the block whose bytes match and reports those bytes.
- [x] 1.3 `LiveBlockState.drifted`, `EditorPresentation.liveBlock`, `MenuPresentation.Command.overwriteDrift` and the shell's overwrite paths carry the digest.

## 2. The cache keys on the digest; bytes live for the read

- [x] 2.1 `FileBytes.read` with a test: bytes identical to `Data(contentsOf:)` for an empty file, a small file and one over the threshold; the large buffer's storage is not malloc's.
- [x] 2.2 `StoreCache` keeps the digest; `StoreReadingCache.file` takes it. `StoreCacheTests` adapted: a same-length rewrite is seen; `heldFiles` no longer implies held bytes.
- [x] 2.3 `StoreReading` and `LiveHostsFile` read through `FileBytes`.

## 3. A rendering is a summary

- [x] 3.1 `BlockSummary`; the `.rendering` derivation holds it and a `.block` derivation holds the bytes, released by `releaseDetail()`. `StoreCacheTests`: after a release the summary answers without a parse and the block bytes are gone; a detail read holds them again.
- [x] 3.2 `ResolvedView.rendered(BlockSummary)`; `EditorPresentation.entryCount` from it; `renderedBlock` only with detail. `EditorPresentationTests` adapted.
- [x] 3.3 `namingTheMatchedProfile` names the digest through `ProfileCatalogue.renderedDigest(for:)`, answered by the cache; `renderedBlock(for:)` stays as the suite's fixture.

## 4. One read serves both

- [x] 4.1 `EditorModel.read` returns `EditorReading` (presentation and activation); test with the `LiveFileReading` seam that one read reads the live file once and the activation agrees with the presentation's applied profiles.
- [x] 4.2 `ShellModel.storeRead` and `init` take both from one read.

## 5. Verification (items 1–4, one commit)

- [x] 5.1 `swift test`: 585 tests, 0 failures; `swift build` clean of warnings in the changed files. `PackagePurityTests` admits `CryptoKit` into the core alongside Foundation.
- [x] 5.2 Release build, ad hoc, against a copy of the store above, launched (window showing the profile) and the window closed: live heap 29.7 MB (was 46 MB), with no `Data` buffer above 1 KB on the heap (was 18 MB in 10); `IOSurface` 2.3 MB and `CoreAnimation` 1.2 MB (were 6.2 and 2.9). Footprint 181 MB, of which 99 MB is thirteen empty `MALLOC_LARGE` regions (3–13 MB each): the composition, the entry lines and the text storage the open window built, freed on close and kept by malloc's large cache, which does not drain on its own (unchanged after 100 s). None is the live file's 4.4 MB. That cache is what task 6 flushes.

## 6. The window is the model's (second commit)

- [x] 6.1 `ShellWindowCloseTests` rewritten: `showWindow()` makes one window; a second call brings the same one forward; closing it leaves `isWindowShowing` false, the view mode text, and — once the close, which animates the window out, is done with it — weak references to the window and the hosting view nil; the draft and selection survive. `ShellWindow` (new), `Launch` (new, the delegate that shows the window at launch and on a Dock reopen), `showWindow()`; the scene, `paneGeneration`, `WindowReader`, `windowChanged` and the update observer gone; the commands on the menu bar scene. Found on the way: with no window scene left, SwiftUI opens the `Settings` scene at launch unless `MenuBarExtra` is declared first; and the scene's window had `.fullSizeContentView`, which the sidebar needs to extend into the title bar.
- [x] 6.2 By hand in the release bundle, driven through System Events: launch shows the window with the title, the sidebar toggle, the plus menu and reload in the toolbar; the plus menu's New Profile presents the name entry as a sheet and Escape cancels it; ⌘F focuses the sidebar search and "track" narrows the lists; ⌘R and ⌘N reach the model through the menu bar (Hazmat, File, Edit, View, Hosts, Window, Help); the close button leaves no window and the application in the menu bar alone (`UIElement`); Open Hazmat in the status menu brings the window back and the Dock icon with it; a window moved to 300,120 and sized 1200×760 relaunches at 300,120 1200×760. `/etc/hosts` untouched throughout.
- [x] 6.3 `footprint` after a close: `IOSurface` 3.5 MB, `CoreAnimation` 0.8–1.4 MB (were 6.2 and 2.9). Live heap 24–25 MB. The large-block cache, however, does not drain: `malloc_zone_pressure_relief` was measured on a 10-block, 80 MB free and returned nothing, as the closed-window-memory change had found. `MallocLargeCache=0` and `MallocSpaceEfficient=1` both return freed large blocks at once; the latter also returns the small zones' free pages. Measured twice each, launched with the window showing the 169k-entry profile, then closed: default open 177–188 MB / closed 82–186 MB (the cache's size varies run to run); space-efficient open 83 MB / closed 42 MB. So the bundle declares `MallocSpaceEfficient=1` in `LSEnvironment`, the verifier checks for it, and a packaging test pins both; launched through LaunchServices the process shows the variable and measures open 82 MB / closed 38 MB, against 106 MB idle before this change and 183 MB after a close.
