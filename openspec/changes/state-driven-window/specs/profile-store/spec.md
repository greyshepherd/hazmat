# Spec Delta

## MODIFIED Requirements

### Requirement: The store has a fixed location and layout

The store MUST have exactly one location at a time, resolved in this order: the
root the environment names, otherwise the location chosen in the window,
otherwise the user's application support directory under `Hazmat/store`. It MUST
hold fragments in `fragments/` and profiles in `profiles/`, and MUST hold one
fragment per `<name>.hosts` and one profile per `<name>.profile`. The environment
override MUST stay authoritative so a development or test store can be kept apart
from the real one, and a chosen location MUST be used instead of the default when
the environment names nothing.

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

## ADDED Requirements

### Requirement: The store can be created before it holds anything

The store MUST be creatable explicitly, which MUST create its directories and
MUST NOT create a profile or a fragment. Creating it MUST succeed for an ordinary
user without privileged access, MUST NOT modify the live hosts file, and MUST be
reported as nothing to do when the store already exists.

#### Scenario: Creating a store
- **WHEN** the store is created at the resolved location
- **THEN** its directories exist and it holds no profiles and no fragments

#### Scenario: Creating it twice
- **WHEN** the store is created where it already exists
- **THEN** nothing changes and the outcome reports that there was nothing to do

#### Scenario: Creating it needs no privilege
- **WHEN** the store is created as an ordinary user
- **THEN** it succeeds and the live hosts file's bytes and modification time are unchanged

### Requirement: The chosen location is remembered and changing it re-reads the store

The location chosen in the window MUST be remembered across launches. Changing it
MUST make every later read and write use the new location, MUST present the new
location's contents rather than merging them with the previous location's, and
MUST leave the previous location's files untouched.

#### Scenario: Remembered across launches
- **WHEN** a location is chosen and the application is launched again
- **THEN** the store is read from that location

#### Scenario: Changing the location
- **WHEN** the location changes to a directory holding different profiles and fragments
- **THEN** the window lists that directory's profiles and fragments

#### Scenario: Changing back
- **WHEN** the location is changed back to the previous directory
- **THEN** that directory's files are exactly as they were left
