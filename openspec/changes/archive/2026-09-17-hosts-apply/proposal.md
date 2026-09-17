# Proposal

## Why

The composition layer produces the bytes of a managed block, but nothing can put
them into `/etc/hosts`. Everything built so far stops at a string, and the file
that matters is owned by root, lives in a directory other tools also write, and
is the reason the incumbent tool is disliked: Gas Mask takes the file over with a
symlink and leaves an ACL that locks every other writer out.

This change carries the rendered bytes across the privilege boundary without
repeating that failure. The store stays the source of truth, the live file is
read before and after so drift is visible rather than silently absorbed, and the
write is atomic, explicitly owned, and leaves no ACL.

Why now: the marker and byte contract is fixed and tested, so the privileged side
can consume bytes without parsing anything. Position within the file is the last
unmeasured input, and no later work (menu bar switcher, packaging) is meaningful
until applying actually works.

## What Changes

- **Read the live file and plan the write.** Read `/etc/hosts`, splice the
  rendered block into it, and hold the exact bytes to write. Everything outside
  the block is carried across byte for byte.
- **Drift detection.** Compare what the live file holds against what the store
  would render now, and report drift instead of overwriting it silently. The
  store is the source of truth, so the remedy is a re-render, not a merge.
- **Block position becomes a configured value, with its default measured.**
  Measure how the resolver treats a duplicate of a name that appears both above
  and below the block, and record the measurement that picks the default.
- **A privileged helper daemon.** It accepts the planned bytes over XPC and
  performs a validated atomic write: temporary file in the same directory,
  flushed, renamed into place, with an explicit mode and owner and no ACL. The
  privileged side parses nothing, composes nothing, and builds no paths.
- **Registration and one-time approval.** Register the helper as a daemon via
  `SMAppService`, surface its state (not registered, awaiting approval, enabled),
  and report registration errors rather than failing silently.
- **A minimal app shell** that hosts the helper's launchd plist, registers it,
  reports its state, and applies a selected profile. It is not the menu bar
  switcher: no menu bar item, no profile editor, no resolved view.

Explicitly out of scope: any user interface beyond that shell (follow-on change
`menu-bar-switcher`), signing, notarization, packaging and the update channel
(follow-on change `shipping`), a command-line surface, and fragment authoring.

## Capabilities

### New Capabilities

- `hosts-apply`: reading the live hosts file, detecting drift, choosing the
  block's position, and carrying out an apply so that the result is verifiable
  and recoverable. The client side of the write.
- `privileged-write`: the privileged boundary itself - the helper's XPC contract,
  its validation and refusal rules, the file semantics of the atomic write (mode,
  ownership, no ACL), and registration with the one-time admin approval.

### Modified Capabilities

None. `hosts-block` already specifies the block, its markers, byte preservation,
and the strip path, and it deliberately leaves position to the caller; choosing a
position is behaviour introduced here, not a change to it. `profile-composition`
is untouched.

## Impact

- Adds a daemon executable target, a minimal app target, a shared XPC protocol,
  and tests. `HazmatCore` gains the client-side apply path (reading the live file,
  drift, position) and keeps its privilege-free properties for those parts.
- Sets the deployment floor to macOS 15, which the previous change left open.
  Helper registration additionally requires a signed app bundle, and the app must
  be able to load before login for the daemon to be bootstrapped at boot.
- Touches `/etc/hosts` for the first time. Reads need no privilege; the write
  happens only through the helper, only inside the managed block, and only with a
  tested mode, owner, and ACL outcome.
- Name resolution on the running machine can be affected for the first time.
  Rollback does not depend on a backup: the block is removed with the strip path
  already specified, or re-applied, because the store holds the source of truth.
