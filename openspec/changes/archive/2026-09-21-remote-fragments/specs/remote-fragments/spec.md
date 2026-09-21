# Spec Delta

## Purpose

A fragment whose text is fetched from a URL — refreshed when it is due, on its
interval, or on demand — so a periodically published hosts file can be managed in
the store instead of pasted into it.

## ADDED Requirements

### Requirement: A remote source is a fragment with a recorded origin

A remote source MUST consist of a fragment holding the fetched text and one
sidecar recording the URL it is fetched from, its refresh interval, and the state
of its last refresh: when it was last attempted, when it last succeeded, the
validators the last answer carried, and the last failure when there was one. The
sidecar MUST be named after the fragment, MUST be plain text, and MUST be held by
the store beside its fragments and profiles. The fragment itself MUST be an
ordinary fragment: listing, composition, stacking, apply, and drift reporting MUST
treat it exactly as a fragment with no origin.

#### Scenario: A fetched fragment is an ordinary fragment
- **WHEN** a source has been fetched and a profile stacks its fragment
- **THEN** the profile composes and applies exactly as it does for a fragment that was never fetched

#### Scenario: The origin travels with the store
- **WHEN** the store's files are copied, or the store is read from another location
- **THEN** every source's URL, interval, validators, and last refresh state are present in the copy

#### Scenario: A sidecar with no fragment
- **WHEN** the store holds a sidecar whose fragment is not there
- **THEN** the source is reported as broken with its reason and is never fetched

### Requirement: A remote source is created, renamed, duplicated, and removed with its origin

Creating a source MUST record its origin and ask for a first fetch. Renaming the
fragment MUST carry its sidecar to the new name, and deleting the fragment MUST
remove its sidecar, so no source is left naming a fragment the store does not
hold and no orphan sidecar is left behind. Duplicating a source's fragment MUST
produce a fragment with no origin, because the copy is a separate text and not a
second source of the same URL. A first fetch that fails MUST leave the source
recorded, with no fragment written and the reason reported.

#### Scenario: Renaming a source
- **WHEN** a remote fragment is renamed
- **THEN** the sidecar is at the new name, the old name holds no sidecar, and the source's URL and state are unchanged

#### Scenario: Deleting a source
- **WHEN** a remote fragment is deleted
- **THEN** its sidecar is removed with it

#### Scenario: A first fetch that fails
- **WHEN** a source is created and its first fetch is refused
- **THEN** the source is listed with the reason, no fragment file is written, and a later refresh can be asked for

#### Scenario: Duplicating a remote fragment
- **WHEN** a fragment that records an origin is duplicated
- **THEN** the copy is an ordinary fragment with no origin, and the original keeps its own

### Requirement: A source is refreshed when it is due, on its interval, and on demand

Each source MUST carry its own interval, and zero MUST mean it is refreshed only
when it is asked for. A source MUST be refreshed at launch when its interval has
elapsed since its last successful refresh, MUST be refreshed while the application
runs once that interval elapses again, and MUST be refreshable on demand from the
source's own row. A source MUST NOT be fetched again before its interval has
elapsed, whatever the outcome of the last attempt.

#### Scenario: Due at launch
- **WHEN** a source's interval has elapsed since its last successful refresh and the application starts
- **THEN** the source is fetched once

#### Scenario: Not yet due
- **WHEN** a source was refreshed successfully inside its interval and the application starts
- **THEN** it is not fetched

#### Scenario: An interval of zero
- **WHEN** a source's interval is zero
- **THEN** it is never fetched by the schedule, and is fetched when its refresh is asked for

#### Scenario: A failed attempt waits for the interval
- **WHEN** a fetch fails
- **THEN** the source is not fetched again before its interval has elapsed, and its row reports the failure

#### Scenario: Refreshed on demand
- **WHEN** a refresh is asked for on a source whose interval has not elapsed
- **THEN** it is fetched

### Requirement: A fetch is conditional, HTTPS only, bounded, and checked before it is stored

A fetch MUST send the validators the last answer carried, and MUST treat a
not-modified answer as no change. It MUST refuse a URL that is not HTTPS, MUST
refuse a redirect that leaves HTTPS, MUST bound the exchange in time, MUST refuse
a body larger than the size bound the applied block already obeys, MUST refuse a
body that is not valid UTF-8, and MUST refuse a body that carries a `hazmat:`
directive. Every refusal MUST be reported with its reason and MUST leave the
fragment exactly as it was.

#### Scenario: The file did not change
- **WHEN** the answer reports that the file is unmodified
- **THEN** the fragment is not written, the refresh is recorded as successful, and the previous text stays

#### Scenario: A body larger than the bound
- **WHEN** the answer carries more bytes than the block bound allows
- **THEN** the fetch is refused with a reason naming the bound, and the fragment keeps the text it had

#### Scenario: A body carrying a removal directive
- **WHEN** the fetched text holds a `hazmat:` directive
- **THEN** the fetch is refused with a reason and the fragment keeps the text it had

#### Scenario: A URL that is not HTTPS
- **WHEN** a source's URL is HTTP or a redirect leads to HTTP
- **THEN** the fetch is refused with a reason and nothing is stored

#### Scenario: The server does not answer
- **WHEN** the exchange exceeds its time bound or the answer carries a failure status
- **THEN** the fetch is refused with the reason the exchange gave and the fragment keeps the text it had

### Requirement: A refresh writes only what changed and keeps the previous text on failure

A refresh MUST write the fetched text through the store's own authoring operation,
so a write that fails leaves the previous text readable and no partial file or
temporary file visible. Text byte-identical to what the fragment already holds
MUST NOT be rewritten. When a fetch or a write fails, the previous text MUST stay
readable, the failure MUST be recorded with its reason, and the reason MUST be
reported in the window.

#### Scenario: The text changed
- **WHEN** a refresh fetches text different from the fragment's
- **THEN** the fragment holds the fetched text and the store holds no temporary file

#### Scenario: The text is identical
- **WHEN** a refresh fetches text byte-identical to the fragment's
- **THEN** the file's bytes and modification time are unchanged

#### Scenario: A failed refresh
- **WHEN** a refresh is refused
- **THEN** the fragment holds the text it had, the failure and its reason are recorded for the source, and the window reports them

### Requirement: A refresh that changes the applied block is re-applied, and drift is never overwritten

A refresh that changes the text MUST count as an edit of the fragment. When the
profile stacking the fragment is the live one and the live block is still
byte-identical to the block that profile rendered before the refresh, the new
block MUST be applied. When the live block differs from that, the live file MUST
be left as it is and drift MUST be reported. A refresh of a fragment no applied
profile stacks MUST NOT change the live file. An apply refused by the privileged
side MUST leave the refreshed text in the store and report the reason.

#### Scenario: The applied profile stacks the refreshed fragment
- **WHEN** a refresh changes a fragment the applied profile stacks and the live block still matches that profile's rendering
- **THEN** the live file holds the newly rendered block and the outcome reports the change

#### Scenario: The live block changed as well
- **WHEN** the live block differs from what the profile rendered before the refresh
- **THEN** the live file is left as it is and drift is reported

#### Scenario: An unapplied profile
- **WHEN** a refresh changes a fragment no applied profile stacks
- **THEN** the live file's bytes and modification time are unchanged

#### Scenario: No approved helper
- **WHEN** the applied profile's fragment is refreshed while the helper is not approved
- **THEN** the store holds the refreshed text, the live file is unchanged, and the refusal is reported with its reason

### Requirement: Refreshing needs no privilege

Creating a source, refreshing it, and recording its state MUST succeed for an
ordinary user without privileged access. The only operation a refresh may involve
the helper in is the apply that follows a change to an applied profile.

#### Scenario: Refreshed before the helper is approved
- **WHEN** a source is created and refreshed while the helper is not registered
- **THEN** the fragment is written and the source's state is recorded

#### Scenario: A fetch writes nothing privileged
- **WHEN** a refresh is refused or the source is not applied
- **THEN** the live file's bytes and modification time are unchanged
