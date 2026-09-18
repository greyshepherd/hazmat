# Tasks

## 1. The system's colours

- [x] 1.1 Replace the palette in the window views (`ShellView`, `SidebarView`, `ContentPane`, `DetailPane`, `StatusRow`, `StatusMark`, `HelperSheetView`, `SettingsView`) with the system's text tiers, materials and separator styles, drop the `\.brand` environment value and the palette parameter the status row, status label, empty state and primary action carry, and let the filled action take the system accent; verified: the package builds and the window names no colour of its own — the only colours left are the hierarchical text styles, `.bar` and `.quaternary` fills, `Color(nsColor: .controlBackgroundColor)` and `.separatorColor`, and the status tones
- [x] 1.2 Map `StatusTone` to the system's status colours in one place in the window so a write state and a helper state still carry a glyph, a word and a colour; verified: `StatusTone.color` is the only mapping, and the sidebar footer, the status row, the fragment editor and the detail pane read it
- [x] 1.3 Delete `BrandColor`, `BrandPalette`, the appearance derivations and their hex, luminance and contrast helpers from app support, keeping `StatusTone`, and rename the window view file that held the palette bridge to `WindowViews.swift`; verified: `swift build` succeeds with no reference to a palette left
- [x] 1.4 Delete the palette contrast test, keep the status-tone mapping covered, and update the isolation test's scene list for the renamed file; verified: `swift test` runs 297 tests with the tone coverage in `WriteStateTests` and `HelperStateTests` still passing

## 2. One window

- [x] 2.1 Replace the window group in the entry point with a single-window scene, keeping the title, the default size, the content minimum and the commands; verified: the built bundle opens one 1080×700 window at the documented default size
- [x] 2.2 Keep the command path's open-then-perform behaviour for a closed window; verified: ⌘N with the window frontmost proceeds in the open window rather than opening another
- [x] 2.3 New Profile no longer produces a second window; verified: ⌘N leaves one window, no tab group, and one running instance, with the name dialog presented in that window
- [x] 2.4 Correct the isolation test that requires the entry point to declare a window group so it requires one window scene instead; verified: `ShellIsolationTests` passes

## 3. One toggle

- [x] 3.1 Remove the toolbar's own sidebar toggle and leave the split view's as the only one; verified: the running bundle's toolbar reports two controls, one of them the system's Hide Sidebar
- [x] 3.2 Keep the Window menu's Toggle Sidebar command and the toggle in agreement through the one sidebar flag; verified: both write the shell model's sidebar flag that the split view's visibility binds to

## 4. The panes' height

- [x] 4.1 Remove the height-forcing `fixedSize` from the window's views so a pane's height comes from the window rather than from its content measured at an unknown width; verified: the package builds with no `fixedSize(horizontal: false, vertical: true)` left in `Sources/HazmatApp`
- [x] 4.2 Measure the split view in every state; verified: the split group measures the window (1080×800) with no store, a store with no profiles, a profile with no layers, a fragment selected and a profile with three layers, where before the fix the first three measured 4922, 4922 and 1434
- [x] 4.3 Verify the previously blank states render inside the window; verified: the first-run pane's heading, explanation, store path and three steps sit inside the frame, and the empty store lists e, g and f with `No layers yet`
- [x] 4.4 Verify the helper sheet still measures its content; verified: 520×379 with its title, its state, its explanation and its three privilege rows
- [x] 4.5 Verify the bug predates this change; verified: a clean HEAD worktree reproduces the same measurements with the same store, so the fix is not compensating for the chrome work

## 5. Verification

- [x] 5.1 Run `swift test` and `Scripts/make-dev-bundle.sh`; verified: the suite runs 297 tests with the one pre-existing failure that a clean HEAD reproduces (the machine holds a store at the default location), the bundle builds and signs, and the launched application shows one window and one sidebar toggle
- [x] 5.2 Check the README for the palette it named; verified: it describes the window as three panes and names no colour, so it needs no change
- [ ] 5.3 Archive `state-driven-window` before this change, so the `app-window` delta this change modifies exists; verified: `openspec validate system-window-chrome --strict` reports no delta warning and the archive applies

## Notes

The colours were verified in the sources and the chrome on the running bundle through the
accessibility API; screen capture is not permitted in this environment, so the rendered
appearance is not verified from a screenshot.
