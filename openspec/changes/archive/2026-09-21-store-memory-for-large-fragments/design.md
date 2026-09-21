# Design

## Context

The cache (`StoreCache`) keys one value per file URL on the file's bytes and one derivation per profile and kind. A reading (`StoreReading`) reads every file, asks the cache for each file's value, and derives compositions and renderings lazily through the cache. `EditorPresentation` is a value the model holds for as long as the window shows it and the menu's schedule needs it.

## Decisions

### D1 — The profiles decide what a read keeps of a fragment

`StoreReading.init` parses the profiles first (they are lines of names) and gathers every fragment they reference. A referenced fragment is asked of the cache as a `FragmentParser.Outcome`, as before. An unreferenced one is asked of the cache as a `FragmentSummary` — its entry count — derived by parsing once and keeping the count. The cache's one-value-per-file rule does the eviction: asking for a summary where a parse was held replaces it, and asking for a parse where a summary was held parses again. So stacking a fragment costs one parse, unstacking it one parse and forty megabytes back, and neither costs anything on the reads in between.

`FragmentReading.outcome` is optional and `entryCount` is stored, so a row asks for the count and composing asks for the parse; `Box.compose` treats a reference whose fragment has no parse as missing, which cannot happen for a fragment the directory listed, since the profiles decided which were parsed.

Alternative considered: a separate eviction pass after the read. Rejected: the cache would need to know which parses the read used, which it learns only as derivations run; the summary-versus-parse choice at read time needs no second pass.

### D2 — Counts are counted, lines are built on demand

`ParsedFragment.entryCount` walks the items; `BlockRenderer.entryCount(_:)` walks the resolved names the way `entries(_:)` groups them. `EditorPresentation.entryCount` is stored by the read and `entryLines` is a computed property, built from the composition. `EntryTableView` takes the composition and builds the lines in its coordinator when the rendering changes, so a body evaluation in table mode passes a value and builds nothing.

### D3 — Exact capacity for what is held

`HostsComposer.resolve` counts the survivors, reserves that capacity, and appends. `resolved` is the array the presentation and the cache hold; `supplied` and `superseded` are transient and grow as they like.

### D4 — One derivation per key, even when two race

`StoreCache.derived` checks the slot again under the lock after deriving; if another derivation of the same key landed first, it answers with that one. The window's read and the menu's activation both derive the selected profile's composition at launch.

## Risks / Trade-offs

- Stacking a large fragment costs a parse the read previously had in hand. Reads run off the main actor and a 4.5 MB parse is tens of milliseconds in release.
- The bytes of an unstacked fragment stay in the cache (4.5 MB for the measured one) so a read can still tell unchanged bytes from changed ones without parsing.
