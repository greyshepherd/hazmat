# Tasks

## 1. The table costs only the rows on screen

- [x] 1.1 Add `Tests/HazmatAppTests/EntryTableViewTests.swift`: a hosted `EntryTableView` shows one row per entry with its address, joined names and `fragment:line`; 100,000 entries produce fewer than 200 row views; a new rendering reloads the rows. Verify the tests fail to build, then add `Sources/HazmatApp/EntryTableView.swift` and verify they pass.
- [x] 1.2 Add a `DetailPaneLayoutTests` case that the pane in table mode hosts an `NSTableView` with the presentation's entry count and no text view; verify it fails on the missing `resolvedViewMode`, then move the mode to `ShellModel`, replace the SwiftUI `Table` and the row cache in `DetailPane` with `EntryTableView`, and verify it passes.

## 2. Closing the window releases what it built

- [x] 2.1 Add `Tests/HazmatAppTests/ShellWindowCloseTests.swift`: posting `willCloseNotification` for the window the model was told about bumps `paneGeneration` and resets `resolvedViewMode` to `.text`; another window closing changes neither. Verify it fails to build, then add the property and the reset to the existing close observer, and verify it passes.
- [x] 2.2 Add a case that a hosted `ShellView` no longer contains the text views it built once the shell window closes; verify it fails, then give both panes `.id(model.paneGeneration)` in `ShellView`, and verify it passes.

## 3. Verification

- [x] 3.1 `swift test`: 551 tests, 0 failures; `swift build` clean of warnings in the changed files.
- [x] 3.2 Measured on the 169,096-entry store in a release build with the fragment stacked by the selected profile: table mode 177 MB footprint / 121 MB live (was 422 / 370); window closed 188 MB / 130 MB live (was 494 / 369), with no table, text view or text storage on the heap; reopening shows the same selection in text mode.
