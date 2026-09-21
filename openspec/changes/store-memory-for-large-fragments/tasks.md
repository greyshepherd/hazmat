# Tasks

## 1. Counts without building

- [x] 1.1 `FragmentParsingTests`: `entryCount` equals `entries.count` with removals and malformed lines among the items. Verify it fails to build, add `ParsedFragment.entryCount`, verify it passes.
- [x] 1.2 `BlockRenderingTests`: `BlockRenderer.entryCount` equals `entries(_:).count` on the work fixture (5, names of one entry sharing a line). Verify it fails to build, add the count, verify it passes.
- [x] 1.3 `EntryTableViewTests` take a composition; `EditorPresentation.entryCount` stored and `entryLines` derived; `EditorModel` and `WriteState` follow. Verify `EditorPresentationTests`, `ShellRefreshTests`, `DetailPaneLayoutTests` stay green.

## 2. A parse only for a stacked fragment

- [x] 2.1 `StoreReadingTests`: a fragment nothing stacks has a count and no parse; a stacked one has both; counting it is one parse. Verify it fails to build, then parse profiles first and summarise unreferenced fragments; verify it passes.
- [x] 2.2 `StoreCacheTests`: reads over an orphan fragment count 4, 4, then 5 when a profile stacks it, 5, then 6 when unstacked, 6. Verify it passes with the same change.

## 3. What is held is held once, and tight

- [x] 3.1 `StoreCacheTests`: two derivations racing for one key share the stored value. Verify it fails (each kept its own), then re-check the slot under the lock after deriving; verify it passes.
- [x] 3.2 `CompositionTests`: 20,000 resolved names have a capacity within malloc's rounding of their count. Verify it fails (39,321), then reserve exactly; verify it passes.

## 4. Verification

- [x] 4.1 `swift test`: 557 tests, 0 failures; `swift build` clean in the changed files.
- [x] 4.2 Measured on the 169,096-entry store in a release build, window closed: stacked by nothing, 35 MB live heap and ~100 MB footprint; stacked by the selected profile, 63 MB live and 125 MB footprint (was 130 MB live after `closed-window-memory`).
