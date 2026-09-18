# Tasks

## 1. Values the window renders

- [x] 1.1 Add a write-state value (in sync, pending with the entry count it would write, blocked with its cause and remedy) computed from the live block state, the rendering and the helper state; verify with tests covering applied, drifted, absent, refused, unreadable and helper-not-enabled
- [x] 1.2 Add a window-phase value (no store, store without profiles, profile without layers, changes pending, in sync, blocked) as one value the scene switches on; verify each phase is produced from a fixture that only satisfies that phase
- [x] 1.3 Add the hosts file path, the entry count and the layer count to the editor presentation; verify with tests against a two-layer profile and with the existing presentation tests still passing
- [x] 1.4 Add the number of entries each layer contributes to the layer list; verify with a fixture whose two layers contribute different entry counts
- [x] 1.5 Add the profiles that use the selected fragment; verify a fragment referenced by two profiles and a fragment referenced by none
- [x] 1.6 Add search text to the shell model and the matching profiles and fragments to the presentation, including the rule that a selected item stays selected while it matches and nothing is selected when it does not; verify with tests for a match, a hidden selection and a cleared search

## 2. Store location and creation

- [x] 2.1 Resolve the store location as the environment override, then the chosen location, then the default; verify a test per branch and a test that a chosen location which does not exist reports as no store rather than falling back
- [x] 2.2 Add explicit store creation that makes the directories and holds nothing; verify creating it, creating it twice reporting nothing to do, and the live hosts file's bytes and modification time being unchanged
- [x] 2.3 Let the shell model re-point its store root, moving the catalogue, the editor model, the applier and the live-file reading together; verify switching to a directory holding different profiles lists those profiles, and switching back leaves the previous directory's files untouched
- [x] 2.4 Persist the chosen location and read it at launch; verify with a preference double and by choosing a location, quitting and relaunching the dev bundle

## 3. The window's panes

- [x] 3.1 Replace the single scrolling column with the three panes (sidebar, content, detail) and remove the fixed 760 point width; verify the window opens, all three panes are visible, and the store's profiles and fragments are listed
- [x] 3.2 Render the sidebar sections with visible selection, per-item detail (fragment entry counts, profile layer counts and the applied mark) and row context menus for rename and duplicate; verify selecting a row changes both other panes
- [x] 3.3 Render the content pane for a selected fragment (labelled name field, monospaced editor, dirty state) and for a selected profile (the layer list with positions, counts, the later-layer-wins caption, drag reordering and removal); verify a drag reorder changes the resolved block and writes the profile
- [x] 3.4 Render the detail pane with the resolved block as selectable monospaced text and as a table of address, names and source fragment, with the entry count, displacements and problems; verify both views, an override, and an unresolvable profile reporting its problem
- [x] 3.5 Render empty states with a label, a one-line description and the action that fills them for both sidebar sections, the layer list and the panes with nothing to show; verify each empty store and empty profile state reads as a next step
- [x] 3.6 Render the selected fragment's using profiles in the detail pane; verify the two-profile and no-profile cases on screen

## 4. Phases, status and the write path

- [x] 4.1 Drive the window from the phase value, with the one prominent action per phase (create store, create first profile, add a fragment, apply, install helper); verify each phase on screen, including the write action being absent when nothing is pending
- [x] 4.2 Remove the permanently disabled controls from the content and move their actions to the toolbar, the row context menu or the pane they act on; verify nothing unusable is rendered and nothing has become unreachable
- [x] 4.3 Add the status row carrying the write state, and the sidebar footer carrying the helper state as a glyph, a word and a colour with the action that resolves it; verify all three helper states and the three write states on screen, and that editing still works while writes are blocked
- [x] 4.4 Add the confirmation before a write, naming the hosts file and the entry count; verify cancelling writes nothing and leaves the state pending
- [x] 4.5 Retain the block an apply replaced for the session and offer the revert, writing it back as a replacement of the block that apply wrote; verify a revert restores the previous block, a revert after an outside edit is refused with its reason, and reverting an install removes the block
- [x] 4.6 Give overwriting drift and removing the block the destructive role with the consequence named before writing; verify both are confirmed and that cancelling leaves the file unchanged

## 5. Commands, search, settings and the shell

- [x] 5.1 Add a commands value carrying the menu bar (File, Edit, Profiles, Fragments, Hosts, Window, Help) and the shortcuts, calling the one shell model; verify each command from the menu bar with the window closed where it applies
- [x] 5.2 Add the sidebar search field bound to the shell model's search state; verify a search narrows both sections and clearing restores the full lists
- [x] 5.3 Add a settings scene with the store location, the folder chooser, the helper state and its install action; verify a location change re-reads the store and that the settings command opens it
- [x] 5.4 Add the helper install sheet reachable from the first-run phase and from the sidebar footer, with the three privileges the helper holds and the states it can be in; verify registration, awaiting approval and enabled
- [x] 5.5 Set the window's title, the default size, the content minimum and size restoration; verify the default on a fresh launch, a restored size, and the minimum
- [x] 5.6 Add the toolbar with the sidebar toggle, the new-item menu and reload with its shortcut and help text; verify each control and that the toolbar carries no action that the current phase cannot perform

## 6. Brand, bundle and appearance

- [x] 6.1 Add the brand palette as code-defined tokens (accent, its darker fill step, the two text tiers, muted, success, warning and danger, and their dark-appearance derivations); verify each pair meets 4.5:1 for text and 3:1 for non-text with a contrast test
- [x] 6.2 Apply the accent once at the root so selections, focus rings and the filled control carry it, and use the two text tiers throughout; verify no control falls back to the system accent
- [x] 6.3 Copy the app icon and the menu-bar mark into the bundle from the development bundle script, add the icon to the bundle's property list, and set the status item's label from the mark; verify the icon in the Dock and menu bar from the built bundle

## 7. Tests and the isolation rules

- [x] 7.1 Update the shell's helper-status assertions to read the presentation instead of the sentence, and keep the state mapping tests passing; verify the updated tests pass
- [x] 7.2 Hold the new window files to the existing scene rules (no store, composition or path names in scenes; the entry point declares scenes only; one shell model shared by every scene including settings and commands); verify the isolation tests pass
- [x] 7.3 Add the app-support tests for the new values (write state, phase, per-layer counts, using profiles, search, location resolution, store creation, revert); verify `swift test` passes with the new tests

## 8. Integration verification

- [x] 8.1 Run the full suite and the development bundle build; verify `swift test` passes and `Scripts/make-dev-bundle.sh` produces a signed bundle that launches
- [x] 8.2 Walk the review's demo steps against the built bundle — reorder a layer and watch the resolved block and pending state change, select a fragment and read its using profiles, apply through the confirmation and revert it, select a profile with no layers, start from no store, and switch to dark appearance; verify each step behaves as its scenario says and record any deviation
