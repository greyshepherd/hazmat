# active-profile Specification

## Purpose

Answers which profile the live hosts file currently represents, by comparing the
block present in the file against the bytes each profile renders, so the answer
survives edits made outside the application.

## Requirements

### Requirement: The active profile is derived from the live file

The active profile MUST be determined from the bytes present in the live hosts
file at the time it is asked. The answer MUST NOT come from stored state, a
preference, or any record the application maintains separately from the file.

#### Scenario: The file is edited outside the application
- **WHEN** another tool changes the block and the active profile is asked for again
- **THEN** the answer reflects the bytes now in the file, not the profile that was applied before

#### Scenario: The derivation is repeatable
- **WHEN** the same file bytes and the same profile renders are derived twice
- **THEN** both derivations report the same result

### Requirement: A profile is active when its rendered bytes are the live block

A profile MUST be reported as active when the block present in the live file is
byte-identical to the block that profile renders now.

#### Scenario: Applied profile is recognised
- **WHEN** a profile was applied and nothing has changed the block since
- **THEN** that profile is reported as the active one

#### Scenario: Off is not a profile
- **WHEN** the live file holds no block
- **THEN** no profile is reported as active

#### Scenario: A profile with no entries is still a profile
- **WHEN** a profile resolves to an empty entry set and its block is applied
- **THEN** that profile is reported as active rather than reported as off

### Requirement: Several matching profiles are all reported

When more than one profile renders the same bytes as the live block, every such
profile MUST be reported, and the result MUST NOT depend on enumeration order.

#### Scenario: Two profiles render identically
- **WHEN** two profiles render the same block and that block is live
- **THEN** both profiles are reported as matching

### Requirement: A block belonging to no profile is reported as drifted

When the live file holds a well-formed block that is not byte-identical to any
profile's rendering, the result MUST report drift and MUST NOT name a profile as
active.

#### Scenario: The block was edited by hand
- **WHEN** a line inside the live block is changed outside the application
- **THEN** the result reports drift and names no active profile

#### Scenario: The profile changed after it was applied
- **WHEN** a profile's fragments change so that its rendering no longer matches the live block
- **THEN** the result reports drift and names no active profile

### Requirement: An unreadable block is distinguished from drift and from off

A live file whose markers cannot be read as one supported block MUST be reported
with that reason, and MUST NOT be reported as drifted, off, or active.

#### Scenario: Doubled markers
- **WHEN** the live file contains two managed blocks
- **THEN** the result reports the block as unreadable with its reason

### Requirement: Deriving the active profile reads and does not write

Deriving the active profile MUST succeed for an ordinary user without privileged
access, and MUST leave the live file and the store unmodified.

#### Scenario: No privilege is required
- **WHEN** the active profile is derived by an unprivileged process
- **THEN** the derivation succeeds and the live file's bytes and modification time are unchanged
