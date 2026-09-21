# Design

## Context

Measured with `footprint` and `heap` on a release build against a store holding a 169,096-entry fragment (4.5 MB), before this change:

| State | Footprint | Live heap |
|---|---|---|
| Fresh launch, window closed | ~90–120 MB | 43 MB |
| The fragment stacked by the selected profile, text mode | 207 MB | 124 MB |
| Same, table mode | 422 MB | 370 MB |
| Then the window closed | 494 MB | 369 MB |

The live heap in table mode was 169k each of `TableOutlineItem`, `AGSubgraph`, `_NSOVRowEntry` and a `[AnyViewTrait]` per row. With zero windows on screen the same objects were still there: SwiftUI's `Window` scene orders the `NSWindow` out and keeps the `NSHostingView` and everything under it, including `DetailPane`'s `@State` row cache and both `NSTextView`s.

What the model itself holds for a stacked 169k fragment — the parsed fragment in `StoreCache` (~40 MB), the composition and `entryLines` (~45 MB) — is out of scope here. It is needed while the profile is shown, and a scheduled remote refresh with the window closed reads `appliedProfiles`, `liveBlock` and `stacks(_:)` from the last presentation to decide a re-apply, so the presentation cannot simply be dropped on close.

## Goals / Non-Goals

**Goals:**

- Table mode costs the rows on screen, not one view per entry.
- Closing the window releases the views the window built.
- Reopening the window shows what it showed: the same selection and draft.

**Non-Goals:**

- Shrinking the parsed fragment, the composition or `entryLines`, or evicting the cache's parse of a fragment no profile stacks.
- Returning freed malloc pages to the OS. `malloc_zone_pressure_relief` after the teardown was measured and made no difference (the slack is fragmented small-allocation pages), so it is not called.

## Decisions

### D1 — `NSTableView` behind a data source, keyed on the rendering

`EntryTableView` is an `NSViewRepresentable` over `NSScrollView` + `NSTableView` with three view-based columns whose cells are reused through `makeView(withIdentifier:)`. The coordinator is the data source and holds `entries: [BlockEntry]`. `updateNSView` reloads only when the `rendering: Data?` it was given differs from the last one (or the count does), so an update that carries the same block does not reload 169k rows.

Alternative considered: keep the SwiftUI `Table` and cap or page the rows. Rejected: a cap hides entries, and the cost is per materialised row, so paging only moves the problem.

### D2 — The view mode is the model's

`ResolvedViewMode` moves from `DetailPane`'s `@State` to `ShellModel.resolvedViewMode`. The pane binds its picker to it; the close handler sets it back to `.text`, so a window that reopens does not immediately rebuild the table. It also lets a test choose the mode.

### D3 — Identity, not teardown

`ShellModel.paneGeneration` is a counter; `ShellView` gives `ContentPane` and `DetailPane` `.id(model.paneGeneration)`. The existing `willCloseNotification` observer (already there to match the Dock presence to the windows) bumps it when the closing window is the shell window, decided by comparing the `ObjectIdentifier` the notification carries with the `shellWindow` the scene told the model about. SwiftUI replaces a subtree whose identity changed, which is what releases the views; the `NavigationSplitView` around them, the sidebar and the search state stay.

Alternative considered: `.id` on the whole `ShellView`. Rejected: it would also rebuild the sidebar and drop the split view's own state for no gain, since the heavy views are in the two panes.

### D4 — The presentation stays

`editor`, `selection`, `fragmentDraft` and the cache are untouched by a close, for the reason in Context: the menu and the remote schedule read them. Reopening shows the same selection and an unsaved draft is still unsaved. The undo stack of the fragment's text view does not survive a close; it did not survive a selection change either.

## Risks / Trade-offs

- An `NSTableView` cell is an `NSTextField`, selectable but not a SwiftUI `Text`; copying a whole row is by selecting rows, as in any AppKit table. The text view remains the place to copy the block.
- SwiftUI tears a replaced subtree down on its next update, not synchronously; the test allows one run-loop turn.
