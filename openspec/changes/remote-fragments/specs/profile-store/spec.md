# Spec Delta

## MODIFIED Requirements

### Requirement: The store has a fixed location and layout

The store MUST have exactly one location at a time, resolved in this order: the
root the environment names, otherwise the location chosen in the window,
otherwise the user's application support directory under `Hazmat/store`. It MUST
hold fragments in `fragments/` and profiles in `profiles/`, and MUST hold one
fragment per `<name>.hosts` and one profile per `<name>.profile`. A fragment
fetched from a URL MUST hold its origin in `remote/<name>.remote`, one sidecar per
such fragment. The environment override MUST stay authoritative so a development
or test store can be kept apart from the real one, and a chosen location MUST be
used instead of the default when the environment names nothing.

#### Scenario: Default location
- **WHEN** a store is opened with nothing in the environment naming a root and no location chosen in the window
- **THEN** its root is the application support directory and its fragments and profiles are read from `fragments/` and `profiles/`

#### Scenario: Overridden location
- **WHEN** the environment names a root
- **THEN** every read and write goes to that root and the default store is left alone

#### Scenario: Chosen location
- **WHEN** a location has been chosen in the window and the environment names no root
- **THEN** every read and write goes to that location and the default store is left alone

#### Scenario: The environment keeps a test store apart
- **WHEN** the environment names a root and a location has also been chosen in the window
- **THEN** the root the environment names is used

#### Scenario: A chosen location that is not there
- **WHEN** the chosen location does not exist
- **THEN** the store reports that it does not exist and creating it is offered, and no read or write falls back to another location

#### Scenario: An origin beside its fragment
- **WHEN** a fragment is fetched from a URL
- **THEN** its origin is recorded in `remote/` under the fragment's own name and no fragment or profile file is disturbed

### Requirement: Profiles and fragments can be created, renamed, and deleted

The store MUST support creating, renaming, duplicating, and deleting a profile or
a fragment. A rename MUST be refused when the target name already exists, and
MUST leave the target's text untouched. Deleting a name the store does not hold
MUST be reported as nothing to do rather than as a failure, unless a sidecar
holds that name, in which case the sidecar is removed and the delete is reported
as done. A fragment that records an origin MUST be renamed and deleted with it: a
rename MUST carry its sidecar to the new name, and a delete MUST remove the
sidecar with the fragment.

#### Scenario: Rename keeps the text
- **WHEN** a fragment is renamed
- **THEN** the new name holds the same text and the old name is gone

#### Scenario: Rename onto an existing name
- **WHEN** a rename targets a name the store already holds
- **THEN** the rename is refused and both files keep the text they had

#### Scenario: Deleting something the store does not hold
- **WHEN** a profile that does not exist is deleted
- **THEN** the outcome reports that nothing was deleted

#### Scenario: Renaming a fragment that records an origin
- **WHEN** a fragment whose origin is recorded in `remote/` is renamed
- **THEN** the sidecar is at the new name, the old name holds no sidecar, and no other fragment's sidecar is touched

#### Scenario: Deleting a fragment that records an origin
- **WHEN** such a fragment is deleted
- **THEN** its sidecar is removed with it and no other file is touched

#### Scenario: Deleting a source whose fragment is not there
- **WHEN** a name holds a sidecar but no fragment file is deleted under it
- **THEN** the sidecar is removed and the outcome reports that the store changed
