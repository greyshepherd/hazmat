# Tasks

## 1. Active-profile derivation in the core

- [x] 1.1 Add the derivation to `HazmatCore` as a function of live bytes plus a list of profile renderings, returning off, unreadable with a reason, drifted, or the matching profiles, and verify tests cover each state, that a profile rendering identical bytes is a match, that two identical renders both match, and that a profile rendering an empty block is active rather than off
- [x] 1.2 Carry a per-profile render problem in the result so a profile whose fragments are missing or malformed is reported rather than silently unmatched, and verify a test shows a broken profile reported alongside a matching one
- [x] 1.3 Verify the derivation writes nothing and needs no privilege, by running its tests as a non-root user and asserting the live file's bytes and modification time are unchanged after a derivation
- [x] 1.4 Verify derivation is deterministic and independent of enumeration order, by deriving the same inputs twice with the profile list in two different orders

## 2. Store-side reading and rendering

- [x] 2.1 Add a store-side call that reads the live file once, renders every profile the store holds, and returns the derivation, and verify a test with several profiles reads the file once and attributes a match correctly
- [x] 2.2 Report a store that does not exist or holds no profiles as its own result, and verify a test covers both cases
- [x] 2.3 Verify rendering a profile that fails does not fail the whole read, by testing a store where one profile references a missing fragment and another renders

## 3. One shared model

- [x] 3.1 Make the app create one model instance and hand it to both scenes, and verify the window's existing behavior is unchanged by the current test suite passing
- [x] 3.2 Put the menu's decision logic in app support as a pure value derived from the state and helper state, and verify tests cover the item set and labels for: one active profile, several matches, no block, a drifted block, a missing store, a not-registered helper, an awaiting-approval helper, and a profile that fails to render
- [x] 3.3 Verify the mapping labels a drift overwrite explicitly and names the profile it would write, and offers no unlabelled overwrite

## 4. The menu bar item

- [x] 4.1 Add the menu bar scene with a title naming the active profile, drift, or off, and verify by running the app that each title appears for the matching state
- [x] 4.2 Build the menu's items from the mapping plus a refresh performed at open time and after each action, and verify a profile file created in the store between two opens appears in the second
- [x] 4.3 Wire activation, deliberate overwrite, Off, and registration to the existing applier and registration, and verify each reports its outcome in the menu
- [x] 4.4 Verify the menu is usable with the window closed: with the window shut, activate a profile from the menu and confirm the file changed

## 5. Supervised verification against the real hosts file

- [x] 5.1 Supervised: save the live file's bytes and metadata, apply a profile from the menu bar, and verify the entries resolve, the bytes outside the block are identical to the saved bytes, and the mode, owner and absent access-control list are unchanged
- [x] 5.2 Supervised: edit a line inside the live block, confirm the title and menu report drift, confirm activating another profile leaves the file alone, then confirm the deliberate overwrite replaces the block and reports that it overwrote drift
- [x] 5.3 Supervised: choose Off and verify the file is byte-identical to the bytes captured before all supervised work, that the title reports off, and that choosing Off again reports nothing to do
- [x] 5.4 Supervised: with the helper unregistered, confirm a menu activation is refused with that cause and the file is unchanged, and confirm the menu offers registration

## 6. Isolation guard

- [x] 6.1 Verify `HazmatCore` still imports no UI or privileged framework and that no new privileged code or XPC method was added, by checking imports and the protocol's methods
- [x] 6.2 Verify `HazmatApp` holds no logic beyond the scenes, by extending the existing source-scanning isolation test to cover the menu bar scene
