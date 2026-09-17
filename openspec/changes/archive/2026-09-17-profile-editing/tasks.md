# Tasks

## 1. The named-block replacement in the apply path

- [x] 1.1 Replace the apply path's overwrite flag with one value carrying both intent and expectation - write only where no block is present, or replace the named block - and verify tests cover: the named block matches and is replaced, the named block differs and is refused with the file unchanged, a named block while the file holds none is refused with the file unchanged, no block named while none is present installs, and no block named while another block is present is refused
- [x] 1.2 Carry the live block in the derivation's drifted state so a deliberate overwrite can name the bytes it replaces, and verify app-support tests show the overwrite carries the block the derivation found
- [x] 1.3 Update the window and the menu bar to name what they read: a switch names the matched profile's rendering, a deliberate overwrite names the drifted block, and a first apply names nothing, verified by the existing apply and menu tests passing with their expectations rewritten
- [x] 1.4 Verify an outcome still distinguishes replacing a block that belonged to a profile from replacing one that did not, and that a refused expectation reports drift, by asserting both outcomes in tests

## 2. Store authoring in the core

- [x] 2.1 Write the store's location and layout down as core types - the root with its environment override, `fragments/`, `profiles/`, one file per name - and verify tests cover the default root, an overridden root that leaves the default alone, and two listings of the same directory returning the same order
- [x] 2.2 Validate a name before any file is touched, and verify tests cover a name holding a path separator, a name holding `..`, a name starting with punctuation, and a refused name leaving no file and no temporary file behind
- [x] 2.3 Implement create, replace, and duplicate for a fragment and a profile as a temporary file in the target directory renamed over the target, and verify tests cover a create in a store whose directories do not exist, an unchanged save leaving the modification time alone, a failed write leaving the previous text, and a read during a write returning one complete version
- [x] 2.4 Implement rename and delete for both kinds, with a rename refused when the target name exists and a delete of an absent name reported as nothing to do, and verify tests cover the text surviving a rename, both texts surviving a refused rename, and an absent delete reporting nothing done
- [x] 2.5 Verify authoring needs no privilege and stays inside the store: run a create, a rename, and a delete as an ordinary user against a temporary root holding a file that must not change, and assert that file's bytes and modification time are untouched
- [x] 2.6 Verify deleting a fragment a profile references succeeds and composing that profile then reports the missing fragment, and that deleting the profile matching the live block leaves the live file's bytes unchanged

## 3. The editor's model in app support

- [x] 3.1 Add a pure model holding the store's profiles and fragments as they are now, the selected fragment's text, the selected profile's layer list, and the actions available in the current state, and verify tests cover a fragment created outside the application appearing in a later read, a store that does not exist reading as an empty store, and a selected fragment whose text is loaded from the store
- [x] 3.2 Build the resolved view in that model from one composition call: every entry with its source fragment, every displaced entry with its source and the fragment that displaced it, and every problem with its fragment and line, and verify tests cover an entry's source, an override, a malformed line's location, a profile referencing a missing fragment showing no entries, and two reads producing equal views
- [x] 3.3 Add the layer-stack operations - add a reference, remove a reference, reorder - writing one reference per line, and verify tests cover a reorder changing which layer wins, a removed layer disappearing from the resolved view, and every layer removed rendering an empty block rather than failing
- [x] 3.4 Add the save path: write the store, then re-apply naming the profile's pre-edit rendering as the block to replace, and verify tests cover the applied profile re-applied over its own bytes, a live block that differs from the pre-edit rendering leaving the file alone and reporting drift, an unapplied profile's edit leaving the live file's modification time unchanged, and a refused apply leaving the store change in place with its reason reported
- [x] 3.5 Verify the model needs no helper: run every store operation with no helper registered and assert the store changes while the live file does not

## 4. The window

- [x] 4.1 Build the editor scene for the store's profiles and fragments - listing, create, rename, duplicate, delete, and editing the selected fragment's text - and verify by running the app against a temporary store that a fragment and a profile can each be created, renamed, edited, and deleted
- [x] 4.2 Add the layer stack and the resolved view to the scene, with problems shown against their fragment and line, and verify by running the app that reordering two layers changes the resolved entries and that a line which is not a host entry is listed with its line number while the save still succeeds
- [x] 4.3 Add saving with the re-apply outcome shown where apply outcomes already appear, and verify by running the app that editing the applied profile changes the live file while editing a profile that is not applied does not
- [x] 4.4 Verify the window and the menu bar agree without a restart: create a profile in the window and confirm the menu lists it, and switch profiles from the menu and confirm the window's active profile and drift both change
- [x] 4.5 Verify a store that does not exist is offered rather than reported as a failure, by launching the app with an empty root and creating the first profile

## 5. Supervised verification against the real store and hosts file

- [x] 5.1 Supervised: save the live file's bytes and metadata, create a profile in the window, apply it, and verify the entries resolve and the bytes outside the block, the mode, the owner, and the absent access-control list are unchanged
- [x] 5.2 Supervised: edit a fragment of the applied profile and confirm the live block becomes the new rendering and the reported outcome says the file changed
- [x] 5.3 Supervised: change a line inside the live block, then edit a fragment of the applied profile and confirm the file is left alone and drift is reported, and confirm the deliberate overwrite then replaces the block and reports that it did
- [x] 5.4 Supervised: delete the applied profile and confirm the live file is unchanged while the window reports the block as drift, then remove the block and confirm the file's bytes match the capture from 5.1
- [x] 5.5 Supervised: with the helper unregistered, edit the applied profile and confirm the store holds the edit, the live file is unchanged, and the refusal is reported with its reason

## 6. Isolation guard

- [x] 6.1 Replace the guard that asserts the editor and the resolved view are absent with a guard for what is still absent - packaging, signing, notarization, and update code - and verify the app-support suite passes
- [x] 6.2 Extend the source-scanning guard so the editor scene decides nothing itself: no store, composition, or file path named in the scene, under the same rule the menu bar scene is held to, verified by the guard passing
- [x] 6.3 Verify `HazmatCore` still imports nothing outside Foundation, that the store writer holds no UI or privileged reference, that the XPC interface still declares two methods, and that no privileged source names a profile - by running the purity tests unchanged
