# Proposal

## Why

With the window closed the application sat at 400–500 MB, and a store holding a 169,096-entry fragment made it easy to reach. Measured on that store in a release build: the resolved block's table view, a SwiftUI `Table`, keeps a view identity, a trait array and an attribute subgraph for every row whether or not it is on screen — about 1.5 KB an entry, 250 MB for the block — and a SwiftUI `Window` that closes keeps its whole view tree, so the table, both `NSTextView`s and their text storage stayed resident with no window on screen (494 MB footprint, 369 MB live heap, a 609 MB peak). The parsed fragment, its composition and its entry lines account for a further ~85 MB; that is the model's, is needed while the profile is shown, and is left for a later change.

## What Changes

- The resolved block's table is an `NSTableView` fed by a data source, the way the block's text is already an `NSTextView`: the rows on screen are the only ones with views, whatever the block's size.
- The view mode of the resolved block (text or table) is the window's, held on the shell model, so the window can put it back to text when it closes.
- Closing the shell window retires the content and detail panes: the model gives them a new identity, so the scene drops what the closed window built and builds the panes afresh when the window shows again. The selection, the fragment draft and the last read are kept; only the views go.

Nothing in what the window shows, offers or writes changes. Measured on the same store after the change: table mode 177 MB (121 MB live); window closed 188 MB (130 MB live), none of it views.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `profile-editor`: the table view of the resolved block costs only the rows on screen.
- `app-window`: closing the window releases what the window built; reopening it shows the same selection, with the resolved block back in text mode.

## Impact

- `Sources/HazmatApp/EntryTableView.swift` (new): the `NSTableView` behind a data source.
- `Sources/HazmatApp/DetailPane.swift`: the table is the new view; the mode and the row cache leave the pane.
- `Sources/HazmatApp/ShellModel.swift`: `resolvedViewMode`, `paneGeneration`, and the close observer that resets one and bumps the other.
- `Sources/HazmatApp/ShellView.swift`: the panes take their identity from the model.
- Tests: `Tests/HazmatAppTests/EntryTableViewTests.swift`, `ShellWindowCloseTests.swift`, `DetailPaneLayoutTests.swift`.
- No new dependencies. No change to the store, the block, the protocol or the helper.
