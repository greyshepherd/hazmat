# Design

## Context

See proposal.md for the measurements. The shape of the code that produced them:

- `EditorModel.read` (`Sources/HazmatAppSupport/EditorModel.swift`) is a pure function of the store and the live file that returns one `EditorPresentation` value. It re-reads and re-parses a fragment for every place that wants a number from it: `entryCount(of:)` for each sidebar row and each layer row, `HostsComposer.compose` for the selected profile, and `renderedBlock(of:)` for every profile when the live file holds a block. `ProfileCatalogue.activation(reading:)` composes and renders every profile again for the menu bar, and `ShellModel.refresh()` calls both.
- `HostsComposer` reads through the `HostsStore` protocol (`fragment(named:) -> String?`), so it has no way to receive an already-parsed fragment.
- `ShellModel` is `@MainActor @Observable`. Reads run synchronously on it; edits and applies already run in `Task.detached` and land through `MainActor.run` with a `busy` flag. Every write to an observable property is guarded (`if latest != editor { editor = latest }`) because the menu rebuilds on any change.
- `FragmentParser`, `ProfileParser`, `Lines`, `AddressSyntax` and `NameSyntax` work on `String`/`Character`; `ManagedBlock.locate` and `BlockSplice.firstEntryIndex` walk `Data` by subscript and decode every line to a `String` to run `contains(token)`.
- `EditorPresentation.rendering` re-runs `BlockRenderer.render` on every access; `DetailPane` shows the block as one `Text` in a `ScrollView`, the displaced list as an eager `ForEach`, and `ContentPane.FragmentEditor` binds the draft to SwiftUI `TextEditor`.
- `PlannedBytes.sizeBound` is `1 << 20`, checked by `PlanVerification.check` on the client and `PrivilegedWriteService` in the daemon; the daemon logs it at startup.
- Measured in release: parse 480 ms per 100k lines; compose 730 ms for two layers (of which ~50 ms is resolution, the rest parsing); render 28 ms; `locate` 117 ms per 5.9 MB; `read` 2–4 s; `refresh` 5–6 s.

Constraints from the existing specs that this design must keep: the store is read when it is asked, never presented from a cache (`profile-editor`, `menu-bar-switcher`); composition is deterministic and explained; the block bytes are stable; nothing but the block ever changes in the live file.

## Goals / Non-Goals

**Goals:**

- A refresh over a store whose bytes have not changed costs file reads and byte comparisons, not parses or compositions.
- A cold read of a 100k-line fragment costs on the order of 100 ms, not seconds.
- No read blocks the main actor for longer than it takes to adopt a value.
- Parser and locator results are bit-identical to today's on every existing fixture, with the CRLF fix the only intended difference.
- The views can hold a 100k-entry block and a 50k-entry displaced list without eager layout.

**Non-Goals:**

- Streaming or partial parsing of a fragment; a fragment is still read whole.
- Incremental composition (re-resolving only the changed layer).
- Changing the store format, the block grammar, the XPC protocol, or how the helper is registered.
- Making the confirmation sheet or the write state summarise size; the entry count it already names is enough.
- Syntax highlighting or structure-aware editing of fragment text.

## Decisions

### D1. The bound becomes 16 MiB, on both sides

`PlannedBytes.sizeBound = 16 << 20`. The daemon and the client share the constant through `HazmatCore`, so both move together; the daemon's startup log line already prints it. Tests that build `sizeBound + 1` bytes keep working. 16 MiB admits roughly 250k–400k typical entries and still refuses a runaway client.

*Alternative considered*: keep 1 MiB and refuse in the editor before an apply. Rejected by the user; the point of the change is that a large store is usable.

### D2. One `StoreReading` per read, built from bytes, shared by everything that read

Introduce in `HazmatCore` a value that reads the store once and answers every question the editor and the menu ask from that one reading:

```swift
public struct StoreReading: Sendable {
    public let fragments: [FragmentID]            // directory listing, sorted
    public let profiles: [ProfileID]
    public func fragment(_ id: FragmentID) -> FragmentReading?   // bytes, text, parse outcome
    public func profile(_ id: ProfileID) -> ProfileReading?      // bytes, text, parse outcome
    public func composition(of profile: ProfileID) throws -> Composition   // memoised per reading
    public func rendering(of profile: ProfileID) throws -> Data           // memoised per reading
}
```

`HostsComposer` gains a second entry point that composes from `[FragmentParser.Outcome]` already in hand (the existing `compose(profile:)` over `HostsStore` stays for tests and the CLI-shaped callers, implemented on top of the same `resolve`). `EditorModel.read` and `ProfileCatalogue.activation` each build one `StoreReading` and take every entry count, layer count, composition and rendering from it. `StoreReading` is a struct whose memo tables live in a `final class` box so a value semantics caller sees one parse per fragment per reading.

Per-read cost after this decision alone: one parse per fragment referenced (not one per row per profile), one composition per profile that needs one, one render each. The 4 s read in the fixture becomes roughly 480 + 240 + 3 × 50 + 3 × 28 ≈ 1 s before D3 and D4.

*Alternative considered*: memoise inside `DirectoryStore`. Rejected: `DirectoryStore` is a `HostsStore` that hands out `String`s; the parse has to live above it, and the composer needs parsed layers, not text.

### D3. A cross-read cache keyed on the bytes, not on file metadata

`StoreSession` holds a `StoreCache` (a `final class`, lock-protected, `Sendable`) that survives across reads. For each URL it keeps the last `Data` read and what was derived from it (parse outcome, and for profiles, the composition and rendering keyed by the generation numbers of the fragments they stacked). Building a `StoreReading` reads every file's bytes (the directory listing and the reads are unconditional — that is what "read when asked" means) and reuses the derived values only when the bytes are equal to the cached bytes. `Data ==` is a length check and a `memcmp`; reading a 5 MB file from the page cache is ~2 ms.

A composition memo entry is keyed by `(profileBytesGeneration, [fragmentGeneration])`, where a generation is an integer bumped whenever a URL's cached bytes change. That makes a profile's composition and rendering reusable exactly when neither its text nor any stacked fragment's bytes changed, and never otherwise.

The cache is bounded by the store: one entry per file, replaced in place. A file that disappears from the listing is evicted.

Steady-state cost per refresh for the fixture: 3 profile reads + 2 fragment reads + `memcmp` over ~6 MB ≈ 5 ms, plus the live-file read and `locate`.

*Alternatives considered*:
- Key on `(mtime, size)`: cheaper, but a same-second same-size rewrite is missed, and the spec forbids a stale presentation. Rejected.
- Hash the bytes: no faster than `memcmp` against the cached copy, and costs a hash pass. Rejected.
- No cross-read cache, rely on D2 + D4: leaves a ~100 ms parse on every refresh, which the menu-bar click would still feel. Rejected as the sole measure; D3 is what makes the steady state free.

### D4. Byte-level parser and locator, same grammar

`FragmentParser`, `ProfileParser` and `Lines` work over `UTF8View`/`UnsafeRawBufferPointer`: lines are found by scanning for `0x0A`, a trailing `0x0D` is dropped, trimming and field splitting look for `0x20`/`0x09`, and `AddressSyntax`/`NameSyntax` get byte-level twins. Every grammar rule is ASCII-only already (a non-ASCII character is refused by `isNameCharacter` and cannot be part of an address), so a byte parser accepts and refuses exactly the same inputs. `String`s are materialised only for what escapes the parser: the address, the names and the problem text.

`ManagedBlock.locate` and `BlockSplice.firstEntryIndex` scan bytes under `withUnsafeBytes`. `locate` looks for the marker token as bytes (`memmem`-style) and decodes a line to `String` only when the token is present, so a 5.9 MB file with no block costs one pass and no allocation.

The measured micro-benchmarks that justify this: `String.split` 59 ms vs `.utf8.split` 9 ms on the fixture; the `Data` subscript loop 11 ms vs 0.07 ms under `withUnsafeBytes`.

**The CRLF difference.** Today `Lines.of` splits on the `Character` `"\n"`, and Swift treats `"\r\n"` as one `Character`, so a CRLF file never splits and is reported as one malformed entry on line 1. The byte parser splits on `0x0A` and drops a trailing `0x0D`, which is what the dead `hasSuffix("\r")` branch always intended. This is a fix; the `profile-composition` delta records it, and an `EdgeCaseTests` case covers a CRLF fragment.

Equivalence is proven by a test that runs the old parser (kept in the test target for the duration of the change, then deleted) and the new one over every fixture in `Tests/HazmatCoreTests/Fixtures` and a generated corpus of edge lines (leading/trailing whitespace, tabs, inline comments, `hazmat:remove`, bad addresses, bad names, duplicates, embedded IPv4 in IPv6, zones), asserting identical `Outcome`s except for CRLF inputs.

### D5. Reads leave the main actor; results are adopted by ticket

`ShellModel` gets one private `read(_ intent: ReadIntent)` used by `refresh()`, `refreshEditor()`, `selectionChanged()` and `searchChanged()`:

- It captures the inputs as values (`session`, `selection`, `StoreSearch(text:)`, and whether the activation is wanted), increments a `readTicket`, and runs the read in `Task.detached`.
- The read returns `(EditorPresentation, ActiveProfileReading?)`; the continuation on `MainActor` drops the result if its ticket is not the latest, then adopts it through the same guarded assignments (`if latest != editor { editor = latest }`) and `adoptFragmentDraft`, which already refuses to overwrite a dirty draft.
- `busy` is not set: a read is not a write, and the window must keep accepting selections and keystrokes. The presentation the window already shows stays until the next one lands.
- `init` performs the first read synchronously so the window's first frame is not the empty phase; with D2–D4 that is ~100 ms for the fixture.
- The status menu's `didBeginTrackingNotification` handler asks for a read the same way; the menu opens on the `reading` it has and its rows update when the new value lands, which SwiftUI `MenuBarExtra` menu content does for observable changes. **Chosen:** the menu keeps the ticketed read rather than a synchronous derivation over the cache; the fallback under Risks is the remedy if a real menu is ever found not to redraw while it is open.

The apply and edit paths keep their `busy` gating and their own `refresh()` after `finish`, which now dispatches a read instead of performing one.

*Alternative considered*: keep reads synchronous and rely on D3 alone. After D3 the steady state is milliseconds, but the first read after an external edit is still a parse, and a 500k-line store would beachball again. The ticketed read is a bounded change to `ShellModel` and closes the class of problem.

### D6. The presentation carries its rendering; the views stop recomputing

`EditorPresentation` stores the rendered block as a `let` set by `read` (it is already computed there for `liveReading`), and `ResolvedView.renderedBlock`/`rendering` become plain accessors. `entryLines` stays a stored array. `DetailPane.blockTable` keeps its `EntryTableRow` array in a `@State` refreshed on presentation change rather than rebuilding it per body.

`DetailPane.blockText` becomes a `NSViewRepresentable` wrapping a non-editable `NSTextView` in an `NSScrollView`, given the rendering as a `String`; `NSTextView` lays out lazily and keeps selection and copy. The displaced list becomes a `List`/`LazyVStack` (a `List` inside the pane's `ScrollView` needs a fixed height; `LazyVStack` inside the existing `ScrollView` is the smaller change and is chosen).

`ContentPane.FragmentEditor` replaces `TextEditor` with the same `NSTextView` wrapper in editable mode. The draft flows out through `textDidChange` into `model.fragmentDraft` as today (the string copy is a few ms at 5 MB and only on keystrokes, not on every body), and flows in only when the model's draft is not what the view holds (a `Coordinator` that ignores echoes of its own edits), so no keystroke round-trips the whole document through SwiftUI's diffing. Undo stays with `NSTextView`'s own undo manager.

*Alternative considered*: keep `TextEditor` and debounce the binding. SwiftUI's `TextEditor` re-diffs the attributed string on every binding write regardless; debouncing hides the freeze without removing it. Rejected.

### D7. The dirty check stays a string comparison

`fragmentIsDirty` compares `fragmentDraft != draftBaseline`; measured at 0 ms for 5 MB (native UTF-8 storage compares by `memcmp`). Nothing to change.

## Risks / Trade-offs

- [The byte parser diverges from the `Character` parser on some input] → the equivalence test in D4 runs both over every fixture and a generated edge corpus; the old parser is deleted only when that test is green.
- [The cache serves a stale derivation] → the key is byte equality of every input, never metadata; a test rewrites a fragment with different bytes of the same length within the same second and asserts the new entry count.
- [Two reads race and the older one lands last] → ticketed adoption in D5; a test starts two reads with a slow store double and asserts the second's result is what remains.
- [A read lands while the user is typing and replaces the draft] → `adoptFragmentDraft` already keeps a dirty draft; a test asserts it for the async path too.
- [The status menu does not redraw while open] → the menu keeps the ticketed read, and this was chosen over the synchronous alternative. If a real `MenuBarExtra` menu is found not to redraw, the fallback is to keep the menu's read synchronous over the D3 cache (steady-state milliseconds) and dispatch only the window's reads.
- [`NSTextView` in a SwiftUI pane changes focus, keyboard-shortcut and Cmd-S behaviour] → the shortcut monitor in `ShellModel` already sees keystrokes before the text system; the existing `WindowShortcutTests` and a manual pass on save/select-all/undo cover it.
- [16 MiB in `/etc/hosts` has system-level cost (mDNSResponder re-reads the file)] → outside this change's control; the bound is a ceiling, not a target, and the proposal notes it.
- [Memory: the cache holds a copy of every file's bytes plus parses and compositions] → bounded by store size (tens of MB for the fixture); evicted when a file leaves the listing.

## Migration Plan

No data or format migration. Ship as one release: a daemon built with the old 1 MiB bound refuses what a new client plans, with the existing "oversized" reason, until the helper is updated — the helper-repair flow already covers a version mismatch. Rollback is a plain downgrade; the store and the live file are untouched by this change.

## Open Questions

None that change the specs or the task breakdown. Whether `MenuBarExtra` redraws an open menu on observable change (D5) is settled in favour of the ticketed read, with the synchronous fallback left under Risks.
