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

- [ ] 6.1 `ShellWindowCloseTests` rewritten: `showWindow()` makes one window; a second call brings the same one forward; closing it leaves `windowShowing` false, the view mode text, and after one run-loop turn a weak reference to the hosting view nil; the draft and selection survive. Verify they fail, then add `ShellWindow`, `showWindow()`, remove the scene, `paneGeneration`, `WindowReader` and `windowChanged`, attach the commands to the settings scene, show the window at launch from the delegate, and verify they pass.
- [ ] 6.2 By hand in the built application: launch shows the window; toolbar plus and reload; sidebar search; the helper sheet, the source sheet, the apply confirmation and the name entry; close and reopen from the menu and from ⌘N; size and position survive a relaunch; Dock presence follows the window.
- [ ] 6.3 `footprint` with the window closed after it was open: `IOSurface` and `CoreAnimation` at the fresh-process level. Recorded here.
