# Proposal

## Why

An application that lives in the menu bar is opened rarely: once configured, it runs in the background. Yet after `store-memory-for-large-fragments` it still held, with the window closed, the parse of every fragment a profile stacked and the selected profile's composition — some 63 MB live for a 169,096-entry fragment, and a launch into the menu bar that never showed the window parsed the fragment for nobody. Nothing that runs with the window closed reads a host name: the menu compares each profile's rendered block with the live file, and the schedule's re-apply reads profile IDs and one block, then composes from disk.

## What Changes

- The cache keeps two things of a file: a summary every read wants (a fragment's entry count, a profile's parse) and, only while a composition has asked for it, the whole parse. `releaseParses()` lets go of every parse and every composition and keeps the bytes, the summaries and the renderings, so a read with no window showing costs file reads and byte compares.
- A reading parses lazily: a fragment is parsed when a composition needs it, and the parse that counted a fragment is the one composing uses.
- A read carries `detail` — the selected profile's composition and the selected fragment's text — only for a window that is showing. Otherwise the presentation holds the rendered block alone (`ResolvedView.rendered`), the entry count is counted from the block's bytes, and the parses are released once the read lands.
- The model launches with no window showing. It reads in full when the scene's window is on screen, and lets everything go again when it closes: the selection and an unsaved draft stay; a clean draft is read again on reopening. The detail pane shows the block only from a read that carried it, so a pane nobody sees decodes nothing.
- The scene reports its window from `viewDidMoveToWindow`, and the model takes a window's first update as the sign it is on screen. A window opened from the menu bar is on screen without the application active, so becoming key is not the sign, and its occlusion state is not reported on the first showing.

Measured on the 169,096-entry store in a release build, live heap: launched into the menu bar 22 MB; window closed after showing the profile that stacks it 42 MB (was 63 MB); the first open from the menu reads in full and shows the block.

## Capabilities

### Modified Capabilities

- `app-window`: the window's parses and composition exist while it is showing; closing lets them go, reopening reads again, a launch that shows no window parses nothing.
- `profile-editor`: a parse is held between reads only while a showing window composes over it.

## Impact

- `Sources/HazmatCore/StoreReadingCache.swift`, `Sources/HazmatAppSupport/StoreCache.swift`: `file(_:bytes:derive:summarise:hold:)`, `parse(_:derive:)`, `releaseParses()`.
- `Sources/HazmatCore/StoreReading.swift`: profiles first, lazy `parse(_:)`, `FragmentReading.entryCount`.
- `Sources/HazmatCore/BlockRenderer.swift`: `entryCount(in:)` from the block's bytes.
- `Sources/HazmatAppSupport/EditorPresentation.swift`, `EditorModel.swift`: `ResolvedView.rendered`, `hasDetail`, `read(selection:search:detail:)`.
- `Sources/HazmatApp/ShellModel.swift`, `ShellView.swift`, `WindowViews.swift`, `DetailPane.swift`: the showing state, the reads it drives, the window's reporting.
- Tests: `StoreCacheTests`, `StoreReadingTests`, `BlockRenderingTests`, `EditorPresentationTests`, `ShellWindowCloseTests`; `ShellWorld` builds a model whose window is showing.
