# Spec Delta

## Purpose

Composes reusable fragments into an ordered profile and resolves them into one
set of host entries, keeping enough provenance to explain every result.

## ADDED Requirements

### Requirement: Fragments are plain files

A fragment MUST be stored as an individual plain-text file containing host
entries in the `/etc/hosts` grammar: an address, a hostname, and optional
aliases, with blank lines and `#` comments permitted. A fragment MUST be usable
without modification by an external text editor or version control system.

#### Scenario: Fragment edited outside the application
- **WHEN** a fragment file is modified by an external editor
- **THEN** the next composition uses the modified content with no import step

#### Scenario: Comments and blank lines are accepted
- **WHEN** a fragment contains comment lines, blank lines, and mixed tabs and spaces
- **THEN** composition succeeds and the comments contribute no entries

### Requirement: A profile is an ordered stack of fragments

A profile MUST reference fragments by identity and MUST preserve the order in
which they are listed. Composition MUST apply the referenced fragments in that
order.

#### Scenario: Order is honoured
- **WHEN** a profile stacks fragments `base`, `project`, `blocklist` in that order
- **THEN** composition applies them in that order

#### Scenario: Missing fragment is reported
- **WHEN** a profile references a fragment that does not exist
- **THEN** composition fails with an error naming the missing fragment

### Requirement: A later layer wins conflicting addresses

When two layers in a profile assign different addresses to the same hostname
within the same address family, the entry from the later layer MUST be the one
present in the resolved set, and the displaced entry MUST NOT be present.

#### Scenario: Later layer overrides earlier
- **WHEN** an earlier fragment maps `api.example.com` to `10.0.0.5` and a later fragment maps it to `127.0.0.1`
- **THEN** the resolved set maps `api.example.com` to `127.0.0.1`

#### Scenario: Reordering changes the winner
- **WHEN** the same two fragments are stacked in the opposite order
- **THEN** the resolved set maps `api.example.com` to `10.0.0.5`

### Requirement: Address families union rather than conflict

When layers assign the same hostname addresses in different families, all
assigned addresses MUST be retained in the resolved set. An IPv4 entry and an
IPv6 entry for one hostname are not a conflict.

#### Scenario: Dual-stack hostname
- **WHEN** one fragment maps `api.example.com` to `127.0.0.1` and another maps it to `::1`
- **THEN** the resolved set contains both `127.0.0.1` and `::1` for `api.example.com`

### Requirement: A layer can remove entries from lower layers

A profile MUST support removal entries that strike a hostname supplied by a
lower layer. A removed hostname MUST NOT appear in the resolved set. Removing a
hostname that no lower layer supplies MUST NOT be an error.

#### Scenario: Blocklist entry is struck
- **WHEN** a lower fragment maps `ads.example.com` to `0.0.0.0` and a later layer removes `ads.example.com`
- **THEN** `ads.example.com` is absent from the resolved set

#### Scenario: Removing an absent hostname is harmless
- **WHEN** a layer removes a hostname no lower layer supplies
- **THEN** composition succeeds and the resolved set is unchanged

### Requirement: Resolution is explained

Every entry in the resolved set MUST record the fragment that supplied it. Every
entry displaced by a conflict MUST be reported alongside the fragment that
supplied it and the fragment that displaced it. The explanation MUST be
available to a caller without recomputing the composition.

#### Scenario: Source of an entry
- **WHEN** a caller asks which fragment supplied a resolved entry
- **THEN** the supplying fragment is identified

#### Scenario: Displaced entries are reported
- **WHEN** a later fragment overrides a hostname from an earlier fragment
- **THEN** the report lists the overridden address, its source fragment, and the fragment that won

### Requirement: Composition is deterministic

For identical fragment content and an identical profile, composition MUST
produce an identical resolved set and an identical report. The result MUST NOT
depend on filesystem enumeration order.

#### Scenario: Repeated composition is identical
- **WHEN** the same profile is composed twice with unchanged inputs
- **THEN** both resolved sets and both reports are equal

#### Scenario: Discovery order does not leak
- **WHEN** fragments are enumerated in a different order but the profile order is unchanged
- **THEN** the resolved set and report are unchanged

### Requirement: Invalid input is reported, never guessed

A malformed entry MUST be reported with its fragment and line number. Malformed
content MUST NOT contribute entries to the resolved set. Composition MUST report
all detected problems rather than stopping at the first.

#### Scenario: Malformed line is located
- **WHEN** a fragment contains a line that is not a valid host entry
- **THEN** the error identifies the fragment and the line number

#### Scenario: All problems are reported
- **WHEN** a fragment contains several malformed lines
- **THEN** each malformed line is reported in one result
