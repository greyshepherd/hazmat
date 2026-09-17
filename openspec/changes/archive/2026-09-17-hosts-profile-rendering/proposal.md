# Proposal

## Why

macOS `/etc/hosts` is a single flat file. Its format has no include directive, no
glob, and no drop-in directory, and the adjacent mechanism (`/etc/resolver`) is
domain-scoped, so it cannot express per-hostname overrides. Anyone who wants
reusable sets of overrides — a base set, a project set, a blocklist — composes
them by hand and re-composes them by hand whenever one changes.

The existing peer implementation in this space, Gas Mask, cannot solve it either.
It takes ownership of `/etc/hosts` by replacing it with a symlink and mutates it
through `cp` and `chmod` as root, which leaves an ACL on the file that blocks
every other tool from writing it. That is the most-reacted issue in its tracker,
and it follows from the design rather than from a defect.

This change builds the composition layer the platform declines to provide, as a
pure core that holds no privilege and never opens `/etc/hosts`.

## What Changes

- **Fragments**: reusable sets of host entries, stored as plain files so they can
  live in git and be edited with any editor.
- **Profiles**: an ordered stack of fragments, plus removal entries.
- **Deterministic renderer** that composes a profile into a resolved entry set:
  - a later layer wins when two layers give a hostname different addresses
  - IPv4 and IPv6 entries for the same hostname union instead of conflicting
  - a removal entry strikes a hostname supplied by a lower layer
- **Provenance** on every resolved entry, recording which fragment supplied it,
  plus a record of entries that lost a conflict. This is the data behind the
  resolved view.
- **Managed-block grammar**: stable markers delimit the region Hazmat owns
  within `/etc/hosts`.
- **Pure splice** that replaces only that region and preserves every remaining
  byte. The shipped file contains a localhost block annotated "Do not change
  this entry", so byte preservation is a requirement rather than a nicety.
- **Byte-stable output**: identical inputs render identical bytes.

Deliberately out of scope for this change: any privileged write, any read or
write of `/etc/hosts`, the privileged helper and its approval flow, drift
detection, the user interface, a CLI, and packaging.

## Capabilities

### New Capabilities

- `profile-composition`: fragment and profile formats, ordered layer
  composition, conflict resolution, removals, address-family union, and the
  provenance needed to explain a resolved entry.
- `hosts-block`: the managed-block grammar within `/etc/hosts`, deterministic
  rendering, and the splice that preserves surrounding content byte-for-byte.

### Modified Capabilities

None. The project has no existing capabilities.

## Impact

- Adds a Swift package with a pure library target and its tests. No AppKit, no
  SwiftUI, no privileged dependency, so it builds and tests without Xcode, root,
  access to system files, or a signing identity.
- Changes no existing code: the repository is scaffolding only.
- Defines the seam consumed by the follow-on changes: `hosts-apply` (privileged
  application of rendered bytes plus drift detection), the menu bar switcher,
  and packaging.
- Reads and writes nothing outside the project directory.
