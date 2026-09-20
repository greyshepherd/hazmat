# Proposal

## Why

A fragment on the order of 100,000 entries (a blocklist, say) is a plausible store, and today the application neither applies it nor stays usable with it. Measured in a release build with a 100,000-line fragment (5.3 MB) stacked by three profiles: `EditorModel.read` takes 2–4 s and `ShellModel.refresh` 5–6 s, all on the main thread, on every search keystroke, every selection change and every click on the menu-bar item; the rendered block (5.9 MB) is refused by the 1 MiB planned-bytes bound before the helper is asked; and the detail pane lays out the whole block as one `Text` and every displaced entry as an eager view.

## What Changes

- Raise the planned-bytes bound from 1 MiB to 16 MiB on both sides of the privileged boundary, so a block of a few hundred thousand short entries can be written while the daemon still refuses arbitrarily large files.
- Parse each fragment once per read. The editor read, the composition and the menu-bar activation share one parse per fragment instead of re-reading and re-parsing the same file for every sidebar row, layer row, composition and profile render. Parses and compositions are memoised on the bytes read, so a store whose files are unchanged costs a file read and a byte comparison, not a parse; the store is still read every time it is asked.
- Move the editor read and the menu-bar activation off the main actor, the way edits and applies already run, so the window and the menu keep responding while a large store is read and show the new presentation when it lands.
- Rewrite the fragment parser and the managed-block locator over UTF-8 bytes rather than `Character`s and per-line `String`s, with identical results on every existing fixture, so a 100,000-line parse costs tens of milliseconds and a 6 MB locate costs single-digit milliseconds.
- Make the detail pane and the fragment editor scale: the text view of the resolved block is an `NSTextView` that lays out only what is visible, the displaced list is lazy, the rendered block is computed once per read instead of on every access, and the fragment editor holds a large draft in an `NSTextView` rather than round-tripping the whole string through a SwiftUI binding on every keystroke.

Nothing in the composition rules, the block grammar, the store layout or the apply contract changes, with one deliberate exception: a fragment with `\r\n` line endings, which the current parser fails to split into lines, is parsed line by line. A store that is small today reads and writes exactly as it does now.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `privileged-write`: the size bound a request is refused past is 16 MiB rather than 1 MiB, documented as such.
- `profile-editor`: the window stays responsive while a large store is read; the resolved block's text and table views, the displaced list and the fragment editor remain usable with 100,000+ entries; the store is still read, not cached, when it is asked.
- `menu-bar-switcher`: opening the menu with a large store does not stall the menu; it still reads the store and the live file at that moment.
- `profile-composition`: a fragment's lines are read the same whether they end in `\n` or `\r\n`. Today a CRLF fragment is not split into lines at all (Swift treats `\r\n` as one `Character`, so the `\n` split never fires) and is reported as one malformed entry on line 1; the byte-level parser fixes this as a side effect and the spec says so.

## Impact

- `Sources/HazmatCore/PlannedBytes.swift`: the bound. `Sources/HazmatPrivileged/PrivilegedWriteService.swift` and `Sources/HazmatDaemon/main.swift` inherit it. Tests that construct `sizeBound + 1` bytes follow the constant.
- `Sources/HazmatCore/Fragment.swift` (`FragmentParser`, `Lines`), `Sources/HazmatCore/Address.swift`, `Sources/HazmatCore/Identifiers.swift` (`NameSyntax`): byte-level parsing.
- `Sources/HazmatCore/ManagedBlock.swift` (`locate`), `Sources/HazmatCore/BlockSplice.swift` (`firstEntryIndex`): byte-level scanning.
- `Sources/HazmatCore/Composition.swift` (`HostsComposer`), `Sources/HazmatCore/Store.swift`/`DirectoryStore`: a parse memo the composer reads through.
- `Sources/HazmatAppSupport/EditorModel.swift`, `EditorPresentation.swift`, `ActiveProfileReading.swift`, `ProfileCatalogue`, `StoreSession.swift`: one parse per fragment per read; the rendered block stored on the presentation; reads that can run off the main actor.
- `Sources/HazmatApp/ShellModel.swift`, `ShellView.swift`, `StatusMenu.swift`: reads dispatched off the main actor and adopted when they land, with the same "unchanged value does not notify" guard the refresh already keeps.
- `Sources/HazmatApp/DetailPane.swift`, `ContentPane.swift`: `NSTextView`-backed text views, a lazy displaced list, no per-body re-render of the block.
- Tests: `HazmatCoreTests` (parser and locator equivalence on the existing fixtures, plus a large-input fixture), `HazmatAppSupportTests` (one parse per fragment per read, memo invalidation on changed bytes, presentation carries the rendering), `HazmatPrivilegedTests` (the new bound).
- No new dependencies. No change to the store format, the block grammar, the XPC protocol or the helper's registration.
