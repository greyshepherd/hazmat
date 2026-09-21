# profile-store Specification

## Purpose

Holds the fragments and profiles Hazmat edits: where they live, how they are laid
out, and what an authoring operation guarantees when it writes.

## Requirements

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

### Requirement: Names are validated before anything is written

A profile or fragment name MUST start with a letter or a digit, MUST contain only
letters, digits, spaces, `.`, `_`, and `-`, MUST NOT end with a space, and MUST NOT
contain `..`. A name outside that grammar MUST be refused with a reason, and no
file or directory MAY be created, replaced, or removed for it.

#### Scenario: A name that would leave the store
- **WHEN** a name containing a path separator or `..` is used
- **THEN** the operation is refused with a reason and the store is unchanged

#### Scenario: A name with a space
- **WHEN** a profile or a fragment is created, renamed, or listed under a name holding an interior space
- **THEN** the name is taken as it stands and the file it names is the one the store reads and writes

#### Scenario: A name with a space where it cannot be kept
- **WHEN** a name carries a leading or trailing space, or any other character outside the grammar
- **THEN** the operation is refused with a reason and the store is unchanged

#### Scenario: A refused name leaves nothing behind
- **WHEN** an operation is refused for its name
- **THEN** no new file and no temporary file is left in the store

### Requirement: The store is created on demand and needs no privilege

Creating a profile, a fragment, or the directories that hold them MUST succeed for
an ordinary user, MUST NOT ask for privileged access, and MUST NOT modify the live
hosts file. A store that does not exist yet MUST be creatable through the same
authoring operations that fill it.

#### Scenario: First file in a store that does not exist
- **WHEN** a fragment or profile is created and the store's directories do not exist
- **THEN** they are created and the file exists with the text that was written

#### Scenario: Authoring needs no privilege
- **WHEN** authoring runs as an ordinary user
- **THEN** it succeeds and the live hosts file's bytes and modification time are unchanged

### Requirement: An authoring operation either completes or leaves the previous text in place

Writing a fragment or a profile MUST replace the file atomically, so a write that
fails leaves the previous text readable and no partial file visible. A failure
MUST be reported with its reason.

#### Scenario: Interrupted write
- **WHEN** a write fails
- **THEN** the previous text is still readable and no temporary file remains

#### Scenario: A reader during a write
- **WHEN** the file is read while it is being replaced
- **THEN** the read returns one complete version of the text

### Requirement: Saving unchanged text does not rewrite the file

Saving text identical to what the file already holds MUST leave the file's bytes
and modification time unchanged, and MUST be reported as nothing to do.

#### Scenario: The same text saved twice
- **WHEN** the same text is saved twice
- **THEN** the second save reports nothing to change and the modification time does not advance

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

### Requirement: Renaming a fragment carries the profiles that reference it

Renaming a fragment MUST rewrite every profile reference to the old name, so no
profile is left naming a fragment the store no longer holds. The rewrite MUST
change nothing else in those files: whitespace, comments, blank lines, and lines
that are not a reference to that fragment stay as they were. A profile that does
not reference the fragment MUST NOT be written at all.

#### Scenario: A referenced fragment is renamed
- **WHEN** a fragment two profiles reference is renamed
- **THEN** both profiles name the new fragment and compose to what they composed before

#### Scenario: The line keeps what surrounds the reference
- **WHEN** a profile line naming the renamed fragment carries leading whitespace or a trailing comment
- **THEN** the line names the new fragment and keeps the whitespace and the comment

#### Scenario: A profile that does not reference the fragment
- **WHEN** a fragment is renamed and a profile never named it
- **THEN** that profile's file is not written

### Requirement: Deleting a referenced fragment or the applied profile is permitted and reported

Deleting a fragment that a profile references MUST be permitted, and composing
that profile MUST report the missing fragment rather than failing the delete or
contributing partial entries. Deleting the profile whose block is live MUST leave
the live file untouched, and the block it leaves behind MUST be reported as
drift.

#### Scenario: Fragment deleted while referenced
- **WHEN** a fragment that a profile references is deleted
- **THEN** the delete succeeds and composing that profile reports the missing fragment

#### Scenario: The applied profile is deleted
- **WHEN** the profile matching the live block is deleted
- **THEN** the live file's bytes are unchanged and the block is reported as drift

### Requirement: Listing reflects the directory and has one order

Listing the store's profiles or fragments MUST reflect the directory's contents
at the time it is asked, MUST NOT come from a cached list, and MUST return the
same order for the same contents.

#### Scenario: A file added by another tool
- **WHEN** a fragment file is created outside the application and the store is listed again
- **THEN** the new fragment appears

#### Scenario: Two listings of the same directory
- **WHEN** the same directory is listed twice with no change
- **THEN** both listings hold the same names in the same order

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
