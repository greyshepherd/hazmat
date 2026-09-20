# Tasks

## 1. A benchmark that says whether anything changed

- [x] 1.1 Add `Tests/HazmatAppSupportTests/ScaleTests.swift` with a generator for a 100,000-line fragment, a 50,000-line overriding layer and three profiles stacking them (the fixture measured in the proposal), plus timing helpers that print through stderr; verify `swift test -c release --filter ScaleTests` runs and prints the baseline numbers for parse, compose, `read`, `activation` and `locate`.
- [x] 1.2 Give the same test hard assertions that are true of the target, not of today: `read` under 300 ms cold and under 30 ms warm, `activation` under 30 ms warm, parse under 150 ms, `locate` on a 6 MB file under 20 ms; verify the test fails now and stays in the suite so the later tasks turn it green (release-only via `#if !DEBUG` guard on the assertions so the debug suite is not gated on optimisation).

## 2. The bound

- [x] 2.1 Set `PlannedBytes.sizeBound` to `16 << 20` and update its doc comment to name 16 MiB and the reason; verify `swift test --filter ApplyTests` and `--filter WriteServiceTests` pass with the existing `sizeBound + 1` cases.
- [x] 2.2 Add a test in `HazmatPrivilegedTests/WriteServiceTests` that a well-formed 100,000-entry block under 16 MiB is not refused for size, and that 16 MiB + 1 is refused with a reason naming both numbers; verify it passes.

## 3. Byte-level parsing and locating (same results, then faster)

- [x] 3.1 Copy the current `FragmentParser`, `ProfileParser`, `Lines`, `AddressSyntax` and `NameSyntax` into `Tests/HazmatCoreTests/ReferenceParser.swift` as a private reference implementation; add `ParserEquivalenceTests` that run reference and production parsers over every file in `Tests/HazmatCoreTests/Fixtures`, over every fragment in `Fixtures/store`, and over a generated corpus of edge lines (leading/trailing tabs and spaces, inline comments, `# hazmat:remove`, unknown directives, bad octets, leading zeros, IPv6 with zones and embedded IPv4, non-ASCII bytes, duplicate names, a line with no terminator) and assert identical `Outcome`s; verify it passes against today's code before anything is rewritten.
- [x] 3.2 Rewrite `Lines.of`/`Lines.trimmed` over `UTF8View` so lines split on `0x0A` and drop one trailing `0x0D`; add a case to `EdgeCaseTests` that a CRLF fragment parses to the same entries and line numbers as its LF twin, and carve that one input out of 3.1's "identical" assertion as the documented exception; verify both tests pass.
- [x] 3.3 Rewrite `FragmentParser.parse`/`parseComment` and `ProfileParser.parse` to walk bytes, materialising `String`s only for addresses, names and problem text; verify `ParserEquivalenceTests`, `FragmentParsingTests`, `ProfileLoadingTests` and `CompositionTests` pass.
- [x] 3.4 Add byte-level `AddressSyntax.family(of:)`/`isIPv4`/`isIPv6` and `NameSyntax.isHostName`/`isIdentifier` twins operating on `UnsafeRawBufferPointer`/`Substring.UTF8View` and switch the parser to them, keeping the `String` entry points as thin wrappers; verify `ParserEquivalenceTests` still passes and the `ScaleTests` parse timing is under 150 ms.
- [x] 3.5 Rewrite `ManagedBlock.locate` and `BlockSplice.firstEntryIndex` under `withUnsafeBytes`, finding the marker token as bytes and decoding a line to `String` only when the token is present; verify `SpliceTests`, `EdgeCaseTests`, `PositionTests` and `ApplyTests` pass and `ScaleTests` reports `locate` under 20 ms on the 6 MB file.
- [x] 3.6 Delete `ReferenceParser.swift` and the equivalence test's dependency on it once 3.2–3.5 are green, keeping the generated edge corpus as ordinary `FragmentParsingTests` cases; verify the full `HazmatCoreTests` suite passes.

## 4. One reading per read

- [x] 4.1 Add `StoreReading` to `HazmatCore` (design D2): built from a `StoreLayout`, it lists both directories once, reads each file's bytes once, parses once, and memoises `composition(of:)`/`rendering(of:)` per reading; add `HostsComposer.compose(profile:layers:)` over parsed outcomes with `compose(profile:)` re-implemented on it; verify new `StoreReadingTests` show one parse per fragment across entry counts, two compositions and three renderings (count via a parse-counting seam), and `CompositionTests` still pass.
- [x] 4.2 Rewrite `EditorModel.read` to build one `StoreReading` and take `fragmentRows`, `layerRows`, `resolved`, `liveReading`'s per-profile renderings and `usingProfiles` from it; store the rendering on `EditorPresentation` as a `let` and make `rendering`/`renderedBlock` plain accessors; verify `EditorModelTests`, `EditorPresentationTests`, `CommandPresentationTests`, `WriteStateTests` and `RevertTests` pass unchanged.
- [x] 4.3 Rewrite `ProfileCatalogue.activation(reading:)` over a `StoreReading`; verify `ProfileCatalogueTests` and `ActiveProfileReadingTests` pass and `ScaleTests` shows `read` under 1.2 s cold with the parser from section 3 (the D2-only target before the cache).

## 5. The cross-read cache

- [x] 5.1 Add `StoreCache` to `HazmatAppSupport` (design D3): per-URL last bytes, generation counter, parse outcome, and per-profile composition/rendering keyed by the stacked fragments' generations; `StoreReading` takes an optional cache and reuses a derivation only when the freshly read bytes equal the cached bytes; verify `StoreCacheTests` cover: same bytes → no re-parse; different bytes of the same length written in the same second → re-parse and new entry count; a fragment change invalidates every profile stacking it and no other; a file removed from the listing is evicted.
- [x] 5.2 Hold one `StoreCache` in `StoreSession` (kept across `repointed(to:)` only when the root is unchanged) and pass it into `EditorModel.read` and `activation`; verify `StoreSessionTests` pass and `ScaleTests` shows `read` and `activation` warm under 30 ms.
- [x] 5.3 Add an `EditorModelTests` case that a fragment rewritten by another tool between two reads changes the entry count, the layer row and the resolved view (the `profile-editor` "changed outside the application" scenario); verify it passes.

## 6. Reads off the main actor

- [x] 6.1 Add a ticketed `read(_:)` to `ShellModel` (design D5) used by `refresh`, `refreshEditor`, `selectionChanged` and `searchChanged`: inputs captured as values, `Task.detached`, result adopted on `MainActor` only when its ticket is the latest, through the existing guarded assignments and `adoptFragmentDraft`; `init` keeps one synchronous first read; verify `ShellIsolationTests` and `WindowShortcutTests` pass and a new `ShellModelReadTests` case shows a slow first read and a fast second read leave the second's presentation in place.
- [x] 6.2 Add a `ShellModelReadTests` case that a read landing over a dirty draft keeps the draft and `fragmentIsDirty`; verify it passes.
- [x] 6.3 Make `finish(_:)` for applies and edits dispatch a read rather than perform one, keeping `busy` cleared before the read lands; verify `WriteStateTests` and the apply/edit cases in `EditorModelTests` pass, and a manual run shows the notice appearing before the resolved view updates.
- [x] 6.4 Route `StatusMenu`'s `didBeginTrackingNotification` and `onAppear` through the same read and confirm on the running app that an open `MenuBarExtra` menu redraws its marks when `reading` changes; if it does not, apply the fallback in design D5 (synchronous activation over the cache for the menu only) and record which was chosen in `design.md`; verify `MenuPresentationTests` pass and the menu over the `ScaleTests` store opens without a stall.

## 7. Views that scale

- [x] 7.1 Add `PlainTextView` (an `NSViewRepresentable` over `NSScrollView`/`NSTextView`, monospaced, selectable, optionally editable, with a `Coordinator` that forwards `textDidChange` and ignores echoes of its own edits) to `HazmatApp`; verify it builds and a preview shows a 100,000-line string scrolling without a stall.
- [x] 7.2 Replace `DetailPane.blockText`'s `Text` with `PlainTextView` in read-only mode fed by the presentation's stored rendering; verify select-all and copy still yield the block bytes, and the pane opens on the `ScaleTests` store without a stall.
- [x] 7.3 Make `DisplacementsView` a `LazyVStack` and keep `blockTable`'s `EntryTableRow` array in `@State` refreshed on presentation change; verify the table and the displaced list open on the `ScaleTests` store without a stall and the existing override scenario still shows both fragments.
- [x] 7.4 Replace `FragmentEditor`'s `TextEditor` with `PlainTextView` in editable mode bound to `model.fragmentDraft` through the coordinator; verify typing in the 100,000-line fragment shows the character at once, the "Unsaved changes" label appears, Cmd-S saves, undo works, and `WindowShortcutTests` pass.

## 8. Closing the loop

- [x] 8.1 Run `swift test` (debug) and `swift test -c release --filter ScaleTests`; verify every suite passes and every `ScaleTests` assertion from 1.2 holds.
- [ ] 8.2 Run the app against a store holding the generated 100,000-line fragment with the helper registered: apply the profile, confirm the live file holds the block, edit one line and save (re-apply), revert, and remove the block; verify each step reports as the specs say and none of them beachballs.
- [x] 8.3 Note the new bound, the CRLF fix and the cache's "bytes must be identical" rule in the release notes or README wherever the previous bound was documented; verify the daemon's startup log names 16777216.
