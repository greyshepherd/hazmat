# Proposal

## Why

The app can apply a profile, but only from its window, and it cannot say which
profile the live file currently represents: the store names profiles, the file
holds a block, and nothing connects the two. A hosts manager is used in short
bursts - flip a profile and get back to work - so switching belongs in the menu
bar, and "which profile is on?" has to be answered from the file rather than from
remembered state, because other tools edit that file.

## What Changes

- **Active profile is derived, not stored.** The block present in the live file is
  compared against every profile's rendered bytes. Matching profiles are named, a
  block matching none is reported as drifted, and no block means the file is off.
- **A menu bar item.** Its title names the active profile; its menu lists the
  store's profiles with the active one marked, activates the chosen profile, and
  offers Off, which removes the block.
- **State is visible where the switch happens.** The menu reports helper state
  (not registered, awaiting approval, enabled) and offers registration; a switch
  without an approved helper is refused with that reason shown.
- **Overwriting drift stays deliberate.** A menu switch never silently replaces a
  block that differs from every profile; the menu offers the overwrite as its own
  item.
- **One shared model.** The state the window and the menu bar both read moves into
  a single instance instead of two copies. Window behavior is otherwise unchanged.

Deliberately out of scope: profile editing, the resolved view, packaging, any
change to the block format, and any new privileged interface.

## Capabilities

### New Capabilities
- `active-profile`: which profile the live file represents, derived from the bytes
  present, and the states it can be in.
- `menu-bar-switcher`: the status item, what its menu offers, and how activation,
  helper state, drift, refusal, and Off appear there.

### Modified Capabilities

None. `hosts-apply`, `hosts-block`, `privileged-write`, and `profile-composition`
keep their requirements: the switcher adds a caller, not new write semantics.

## Impact

- Adds a menu bar scene and active-profile derivation; no new privilege, no new
  dependency, no change to the daemon's interface.
- `ShellModel` becomes shared state for both scenes.
- Reads the store directory and the live hosts file; writes only through the
  existing approved-helper path.
- Deployment floor stays macOS 15.
