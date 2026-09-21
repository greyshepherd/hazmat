# Proposal

## Why

After `closed-window-memory`, what the application held with the window closed was the model's own data. Measured on a store holding a 169,096-entry fragment: the cache kept that fragment's full parse (~40 MB) whether or not any profile stacked it, to serve one number on its sidebar row; every read built the block's entry lines (169k `BlockEntry`s, each with its own array) and held them on the presentation to show a count; a fragment's entry count was taken by building its entries to count them; and a composition's resolved names were kept in an array grown by appending, with up to a second, empty copy of itself in reserved capacity. Two readings deriving the same composition at once each kept their own.

## What Changes

- A reading parses the profiles first and holds a fragment's parse only when some profile stacks it. A fragment nothing stacks is read for its bytes and its entry count; the cache keeps the count in place of the parse, and a profile that later stacks the fragment parses it once more.
- `ParsedFragment.entryCount` and `BlockRenderer.entryCount(_:)` count in place. The presentation carries the block's entry count; its entry lines are built only when the table asks, from the composition, once per rendering.
- A composition's resolved names are stored with no growth slack.
- A derivation that raced another for the same key answers with the value the cache stored.

Nothing in what is shown, offered or written changes. Measured on the same store, window closed: the fragment stacked by nothing, 35 MB live heap (was 43 MB with only that fragment's parse, then more); stacked by the selected profile, 63 MB live (was 130 MB).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `profile-editor`: a parse is reused between reads only for a fragment some profile stacks; the count of a fragment nothing stacks is what is reused.

## Impact

- `Sources/HazmatCore/StoreReading.swift`: profiles first; `FragmentReading.entryCount`, `outcome` optional; `FragmentSummary`.
- `Sources/HazmatCore/Fragment.swift`, `BlockRenderer.swift`, `Composition.swift`: in-place counts; exact-capacity `resolved`.
- `Sources/HazmatAppSupport/EditorPresentation.swift`, `EditorModel.swift`, `WriteState.swift`, `StoreCache.swift`: `entryCount` stored, `entryLines` derived; the racing derivation.
- `Sources/HazmatApp/EntryTableView.swift`, `DetailPane.swift`: the table builds its rows from the composition once per rendering.
- Tests: `StoreReadingTests`, `StoreCacheTests`, `FragmentParsingTests`, `BlockRenderingTests`, `CompositionTests`, `EntryTableViewTests`.
