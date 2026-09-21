# Design

## Context

With the window closed the application needs: which profile is applied (each profile's rendered block against the live file — bytes), the remote schedule (sidecars; on a refresh that writes, `appliedProfiles`, `liveBlock` and `stacks(_:)` from the last presentation, then a composition from disk), and the menu's commands (IDs and flags). None of it reads a host name. What kept the names alive was the cache tying a file's generation to its parse — dropping the parse would have invalidated the rendering keyed on it — and the model keeping the last presentation whole.

## Decisions

### D1 — Generation on the bytes; parse held only while asked for

`StoreCache` keeps per file `(bytes, generation, summary, parse?)`. `file(_:bytes:derive:summarise:hold:)` derives only when the bytes changed, stores the summary, and holds the parse when `hold` says so (a fragment some profile stacks; a profile's summary is its parse). `parse(_:derive:)` answers the held parse or derives and holds one. `releaseParses()` nils every parse and drops `.composition` derivations; renderings stay keyed on generations that did not change. So after a release, a read that wants counts and renderings parses nothing, and one that composes parses each layer once.

### D2 — Lazy parse in the reading

`StoreReading` parses the profiles first (lines of names), then records each fragment's bytes and asks the cache for its summary — holding the parse for stacked fragments, since composing will want it and the one parse serves the count and the composition. `parse(_:)` is memoised per reading in `Box` and goes through the cache. Without a cache, the reading parses at init and keeps the parses for its own lifetime.

### D3 — `detail` on the read, `.rendered` on the presentation

`EditorModel.read(selection:search:detail:)` derives the rendering first (reused across reads on its own) and the composition only with `detail`. A read without it decodes no fragment text and carries `ResolvedView.rendered(Data)`; `entryCount` is counted from the block's bytes (`BlockRenderer.entryCount(in:)`), so the menu's confirmation still has the number. `hasDetail` says which kind a presentation is; the detail pane shows the block only from one that has it.

### D4 — The model's showing state

`windowShowing` starts `false` (a launch parameter, `true` for the tests of window behaviour). Reads pass it as `detail`, and a read without detail releases the parses when it lands. The `willClose` observer, when the closing window is the shell window, resets the view mode, bumps the pane identity, clears the flag and asks for a read. `windowChanged(_:)` with a window on screen, and `NSWindow.didUpdateNotification` for the shell window once it is on screen, set the flag and ask for a read in full. `didUpdate` fires for every window on every update, so the handler returns first on the common case.

Alternatives measured and rejected: `didBecomeKey` (a window opened from the menu bar extra is on screen without the application active, so it never comes); `didChangeOcclusionState` (not delivered for the shell window's first showing); `viewDidMoveToWindow` alone (the view moves in before the window is visible).

### D5 — The reporter

`WindowReader` is an `NSView` subclass reporting from `viewDidMoveToWindow`, not from an async block after `makeNSView` that a window open since launch may never follow with an update. The window's keyboard shortcuts depend on the same report.

## Risks / Trade-offs

- Opening the window parses and composes the selected profile's layers again: ~100–200 ms for a 169k fragment in release, off the main actor; the panes show the block when it lands.
- A clean draft is let go on close and read again on reopening; an unsaved one is kept, as before.
- The footprint after a session stays above the live heap by the allocator's fragmentation (freed small objects interleaved with kept ones). Measured: a plain process returns most of a freed 160 MB of small objects on its own and `malloc_zone_pressure_relief` adds nothing, so it is not called.
