# Design

## Context

Constraints that shape the approach. See proposal.md for motivation.

- `/etc/hosts` is one flat file with no include directive, no glob, and no
  drop-in directory. The format is BSD 4.2 lineage and unchanged on the current
  system.
- The file is consumed by mDNSResponder rather than by a per-process library
  module, so there is no per-application seam to exploit.
- `/etc/resolver` delegates whole domains to a nameserver. It cannot express
  individual hostname overrides, and relying on it would mean shipping and
  supervising a DNS daemon.
- The shipped file carries a vendor header and loopback entries annotated
  "Do not change this entry". Byte preservation is a platform constraint.
- The incumbent implementation takes ownership by replacing `/etc/hosts` with a
  symlink and mutating it through `cp` and `chmod` as root. That leaves an ACL
  which blocks other writers, and it is the most-reacted issue in its tracker.
  It is also why `cp`-based escalation is ruled out here.
- Repository state: scaffolding only. No code, no deployed behaviour, no
  existing capabilities.

## Goals / Non-Goals

**Goals:**

- Turn fragments and a profile into a resolved entry set with provenance.
- Produce identical bytes for identical inputs, independent of filesystem
  enumeration order.
- Touch only the managed block, and provably restore the original file when the
  block is removed.
- Publish an output contract the privileged side can consume without parsing:
  rendered bytes plus independently locatable markers.
- Test without root, without Xcode, and without access to `/etc/hosts`.

**Non-Goals:**

- Reading or writing `/etc/hosts`. This change produces and consumes text only.
  Follow-on change: `hosts-apply`.
- The privileged helper, its one-time approval flow, and drift detection.
  Follow-on change: `hosts-apply`.
- Any user interface, including the resolved view. This change produces the data
  that view will display. Follow-on change: `menu-bar-switcher`.
- Signing, notarization, packaging, and the update channel. Follow-on change:
  `shipping`.
- A command-line surface. Deferred; see Open Questions.
- Fragment authoring UI, and fragment discovery outside the configured
  directory.

## Decisions

**1. Managed block, not seizure and not whole-file rewrite.**
Hazmat owns a delimited region and preserves everything around it. Seizure makes
the live file the source of truth, so external edits silently become part of a
profile and any tool that replaces the file destroys the profile. A whole-file
rewrite leaves nowhere for other tools' entries to live.
_Alternatives_: symlink seizure, full regeneration. Both rejected.

**2. The store is the source of truth; `/etc/hosts` is a rendered artifact.**
Every byte in the block is derivable from fragments plus the profile. Recovery is
then a re-render rather than a reconstruction, which is what later makes drift
detection safe.

**3. The renderer resolves conflicts itself.**
Resolution is keyed on `(name, address family)` and a later layer wins. Because
the renderer emits each name once per family, the result does not depend on
whether mDNSResponder honours the first or the last duplicate line, so that
unmeasured platform detail cannot affect output.
_Alternative_: emit duplicates and let the resolver decide. Rejected: it makes
behaviour depend on an undocumented rule.

**4. The resolution key is every name on an entry, aliases included.**
`127.0.0.1 api.example api` introduces `api` as a resolvable name. Keying only on
the primary hostname would let an alias win or lose silently.
_Alternative_: key on the primary hostname only. Rejected: it hides conflicts.

**5. Entry order is the winning layer's order, then line order within it.**
Deterministic, stable across runs, and tied to a choice the author made.
_Alternative_: sort by hostname. Tidy diffs, but discards the author's grouping.

**6. Fragments are plain files; a profile is an ordered list.**
A fragment is a plain-text hosts file. A profile is a plain-text file naming
fragments one per line in stack order, comments permitted. No structured format
is introduced: there is no metadata to carry yet, and YAML or JSON would add a
dependency, a versioning problem, and a parser to test.
_Alternative_: structured profile format. Rejected as premature.

**7. Removals are directives inside a fragment, written as comments.**
`# hazmat:remove ads.example.com`. Keeping removals in a fragment preserves the
layer model (a layer removes what lower layers added) and keeps every fragment a
valid hosts file, so an external editor sees nothing unexpected. Removal
directives are never emitted into the rendered block.
_Alternative_: a removal section in the profile. Rejected: it splits related
content across two files.

**8. Markers are comments, distinctive and versioned.**

```
# >>> hazmat:managed v1 >>>
```

with a matching end marker. A leading `#` keeps a spliced file a valid hosts
file, a distinctive token avoids colliding with ordinary content, and the version
lets a future format be recognised and refused rather than misread.

**9. The splice is position-agnostic.**
It preserves the relative order of existing lines and restores them exactly on
removal, so where the block lands is a separate concern. That separation is
deliberate: position interacts with how foreign entries are ordered in the file,
and that is not measured yet. See Risks.

**10. Rendered bytes are the interface to the privileged side.**
`hosts-apply` will receive bytes plus markers and perform a validated atomic
write with an explicit mode and ownership, and no ACL. Nothing in the privileged
path parses, composes, or builds paths. This is why the renderer's output
contract includes independently locatable markers rather than one opaque
document. Recorded here because it fixes this change's output shape.

## Risks / Trade-offs

- **Foreign entries may shadow block entries.** If the resolver honours the first
  matching line, an entry written above the block by another tool wins, and the
  override appears to do nothing. → Block position is a parameter rather than a
  hard-coded choice, and the behaviour is measured before `hosts-apply` ships.
  De-duplication inside the block confines the risk to foreign entries, never to
  Hazmat's own output.
- **Another tool replaces or truncates the file.** → Not detected here, by
  design. Recovery is a re-render, because the store is the source of truth.
  Detection arrives with `hosts-apply`.
- **Byte preservation can break invisibly.** A read-modify-write that normalises
  a trailing newline or line endings damages the file with no obvious symptom. →
  Two property tests, both specified as scenarios: splice-then-remove equals the
  original bytes, and splice is idempotent.
- **Hand-edited fragments can be malformed.** → Every problem is reported with
  fragment and line number, and malformed lines contribute nothing. No guessing
  and no partial application.
- **Marker collision or loss.** A tool could strip comments, or a user could
  paste a marker string. → Distinctive versioned markers; multiple,
  unterminated, or malformed markers are refused with the input left unchanged
  rather than half-edited.
- **Alias conflicts are less obvious than hostname conflicts.** → The resolution
  report names the displaced entry and its source fragment, so the resolved view
  can explain it.

## Migration Plan

Not applicable. The project is greenfield: no deployed behaviour, no stored data,
no existing users. Rollback is deleting the change.

## Open Questions

1. **Minimum deployment target** (13, 14, 15, or 26). The renderer is plain Swift
   and needs no platform declaration, so nothing here depends on the answer. It
   matters later: `SMAppService.daemon` requires macOS 13, so the privileged
   helper in `hosts-apply` sets a floor of 13 regardless. It also decides test
   framework availability.
2. **Whether Hazmat ships a command-line surface**, and its shape.
3. **Packaging and update channel**: DMG, Homebrew cask, or a Sparkle feed.
4. **The helper's XPC protocol and one-time approval flow**, which belong to
   `hosts-apply`.
