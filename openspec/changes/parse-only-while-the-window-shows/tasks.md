# Tasks

## 1. The cache and the reading

- [x] 1.1 `StoreCacheTests`: after `releaseParses()`, a read that asks counts and renderings parses nothing; one that composes parses each stacked fragment once and holds them. A fragment nothing stacks is counted without holding its parse; stacking it parses it once more. Verify they fail to build, then implement `file(_:bytes:derive:summarise:hold:)`, `parse(_:derive:)`, `releaseParses()`; verify they pass.
- [x] 1.2 `StoreReadingTests`: the parse that counted a fragment is the one `parse(_:)` and composing use. Verify it fails to build, then parse lazily through the cache; verify it passes.

## 2. A read without detail

- [x] 2.1 `EditorPresentationTests`: a read with `detail: false` matches the full one in rendering, count, live state, rows and write state, and carries no composition and no fragment text. Verify it fails to build, then add `ResolvedView.rendered`, `hasDetail`, `entryCount(in:)` and the flag; verify it passes.

## 3. The model

- [x] 3.1 `ShellWindowCloseTests`: closing lets the parses go (none held, the block kept), a read with the window closed composes nothing, showing the window parses the layers again; an edited draft survives a close and a clean one is read again; nothing is parsed until the window shows. Verify each fails, then implement the showing state, the closed read and its release, and the reads on showing; verify they pass.
- [x] 3.2 `ShellWindowCloseTests`: the scene needs no hand-telling of its window, and builds no text view for a closed window. Verify it fails, then report from `viewDidMoveToWindow` and show the block only from a detailed read; verify it passes.
- [x] 3.3 The showing signal: measured `didBecomeKey` (never for a window opened from the menu bar), `didChangeOcclusionState` (not on the first showing), settled on `didUpdate`; the tests' `show(_:)` posts it.

## 4. Verification

- [x] 4.1 `swift test`: 570 tests, 0 failures; `swift build` clean of warnings in the changed files.
- [x] 4.2 Release probe on the 169,096-entry store, live heap: launched into the menu bar 22 MB; first open from the menu reads in full and shows 169,097 entries; closed after table mode 42 MB; reopened shows the block in text mode; closed 42 MB.
