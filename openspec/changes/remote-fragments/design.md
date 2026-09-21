# Design

## Context

See `proposal.md` — Why. What shapes the approach:

- The store is plain text with one file per name, and any editor or version
  control system may change it. Composition reads fragments by name through a
  protocol that has no enumeration, and the privileged helper only ever writes
  the rendered block, never a store file.
- The applied-block rule already exists for edits: a change to a fragment is
  re-applied when the applied profile stacks it and the live block still matches
  what that profile rendered, and drift is reported instead. Auto-refresh must
  fit that rule rather than invent a second one.
- The core library imports Foundation and nothing else, and the test suite never
  reaches the network or runs as root.
- The application is a menu-bar resident that stays running, so a repeating due
  check is a usable schedule, and the helper's writes are the only privileged
  step in the system.

## Goals / Non-Goals

**Goals:**

- A remote hosts file becomes a fragment with an origin, with no change to
  composition, the block grammar, the profile format, or the privileged boundary.
- A refresh is the same operation as an edit, so re-apply, drift, refusal, and
  the notice all behave as they already do.
- The network is the least trusted part of the system: bounded, conditional,
  HTTPS only, and never able to store text the block path would not accept.

**Non-Goals:**

- Mirroring a remote file faithfully: Hazmat stores what it fetched, and a body
  it refuses is not stored at all. No merge, no diff, no three-way resolution.
- Fetching in the helper or the daemon. The privileged side keeps writing only
  the block, and knows nothing about URLs.
- A per-source history, so a refresh cannot be undone to an earlier fetch.
- Fetching other hosts-file-like formats (adblock, dnsmasq) or converting them.

## Decisions

### D1: The origin is a sidecar, and the fetched text is an ordinary fragment

A source is `fragments/<name>.hosts` (the fetched text) plus
`remote/<name>.remote` (the origin). Considerations:

- *A header inside the fragment's own comments.* Rejected: the fragment parser
  treats a comment whose first field starts with `hazmat:` as a directive and
  reports an unknown one as a problem, so machine state in the fragment would
  either widen the fragment grammar or break a profile. It would also mix
  fetch state into the file a user is most likely to edit by hand.
- *A single catalogue for every source.* Rejected: every refresh of every source
  would rewrite one file, a rename of one fragment would rewrite it, and two
  writers would contend on it for no benefit.
- *A separate `remote/` fragment namespace.* Rejected: composition, listing,
  apply, and reference resolution would need to know about two namespaces for the
  same kind of thing.

The chosen shape keeps the sidecar invisible to composition: nothing that reads a
fragment has to know an origin exists, and the origin survives a copied store
because it is in the store.

### D2: The sidecar is JSON, plain text, and versioned

`remote/<name>.remote` holds one JSON object: a format version, the URL, the
interval in seconds, and the refresh state (last attempt, last success, the two
validators, the last failure's reason). Foundation's `Codable` in the core keeps
the format exact and the round trip total.

*Alternatives considered:* `key value` lines, which need escaping rules for URLs
and dates and lose unknown keys silently; a property list, which is heavier and
no more readable. JSON is plain text, survives version control, and a missing or
unparseable sidecar is simply a broken source — reported, never fetched.

### D3: The fetch lives in the application, the decisions live in app support

`HazmatApp` owns the `URLSession` exchange, `HazmatAppSupport` owns what to do
with an answer, and `HazmatCore` owns the sidecar and the bounds. *Why:* the core
stays Foundation-only and pure, the suite tests every refusal and every write
through a fetch seam with no network, and the network dependency stays in the
target that already links Sparkle.

### D4: A fetch is conditional and a not-modified answer is not a write

The last answer's `ETag` and `Last-Modified` are sent back as `If-None-Match` and
`If-Modified-Since`. A not-modified answer records a successful refresh and
writes nothing, so a source that has not changed costs one exchange and no file
write, and the fragment's modification time stays honest.

### D5: What a fetch refuses

HTTPS only, including every redirect; a bounded exchange time; a body no larger
than the applied block's size bound (one number for the whole system — text that
could not be applied is not worth storing); valid UTF-8; and no `hazmat:`
directive.

The directive rule is the interesting one: `# hazmat:remove` removes a name a
lower layer supplied, which is a tool for the person authoring the stack, not
something a published blocklist should be able to do to entries below it. A
remote body carrying one is refused whole, with the reason, rather than silently
ignored, so the user learns the source is not a plain hosts file.

### D6: A refresh is an edit, performed one writer at a time

A successful fetch with changed text goes through the same store write and the
same re-apply path an edit takes: write the fragment, then apply when the applied
profile stacks it and the live block still matches the block that profile
rendered before the refresh, otherwise report drift. *Why:* one rule for "the
store changed underneath the applied profile" is easier to trust than two, and
drift is the existing, tested answer to a block that no longer matches.

Refreshes run one at a time and never concurrently with a user edit, because both
plan from a presentation of the store that the other can change. A refresh that
loses the race is simply due again.

### D7: The schedule is per source, with a floor

Each sidecar carries its own interval: default 24 hours, minimum 15 minutes, and
zero for "only when asked". A due check runs at launch and then on a repeating
timer; the on-demand action runs regardless of the interval. A failed attempt
waits out the interval like a successful one, so a source that is down is not
hammered.

### D8: The sidebar lists sources, including ones with no fragment yet

The fragment rows are the union of `fragments/` and `remote/`: a source whose
first fetch failed has a sidecar and no fragment, and it must still be visible,
retryable, and deletable. Deleting a name whose fragment is absent but whose
sidecar is present removes the sidecar and reports a change; without either,
nothing to do.

### D9: A remote fragment's text is read-only in the window

The file stays ordinary text that any editor may change, but the window presents
it read-only with its URL, because the next refresh replaces it. Authoring by
hand stays possible where it belongs: in the file.

### D10: Rename and delete carry the sidecar in the store writer

The store writer is the one place that moves and removes fragment files, so the
sidecar follows there and nowhere else. Composition, listing, and the editor
never move files.

## Risks / Trade-offs

- [The live file changes without a click] → The block is replaced only when it
  still matches what the applied profile rendered; drift is reported instead. The
  fragment row names its URL, the status row reports every refresh, and a source
  may be left at "only when asked".
- [A hostile or mistaken source shapes the block] → HTTPS only, size-bounded,
  `hazmat:` directives refused, and only entries a profile resolves can reach the
  live file.
- [A refresh blocks the window] → Exchanges run off the main actor, one at a
  time, bounded in time; the window reads the store as it is and adopts the
  result when it lands.
- [Refresh and edit interleave] → One writer at a time, takes planned from a
  presentation, and drift instead of an overwrite when the block moved.
- [Sidecar and fragment drift apart] → A sidecar without a fragment is reported
  and never fetched; a rename or delete moves both together; the window lists
  both names and offers removing the source.
- [The sidecar format changes later] → The version field is read first, and an
  unreadable or unknown version is reported as a broken source rather than
  guessed at.

## Migration Plan

Additive: an existing store keeps working untouched. `remote/` appears the first
time a source is created; a store with no sidecars behaves exactly as it does
today. Nothing in the block, the profile format, or the XPC protocol changes, so
no migration or rollback step is needed.

## Open Questions

None that change the specs, the approach, or the tasks. Where the interval is
edited (the add-source sheet versus the row's own sheet) is a presentation
detail the tasks settle.
