# Spec Delta

## MODIFIED Requirements

### Requirement: The window edits the store

The window MUST list the store's profiles and fragments, MUST offer creating,
renaming, duplicating, and deleting both, and MUST read the store when it is
asked rather than presenting a cached list. Work derived from a file's bytes
(its parse, a profile's composition, its rendered block) MAY be reused between
reads only while the bytes read are identical; a file whose bytes changed MUST
be parsed again on the next read. A fragment's parse MUST be held between reads
only while some profile stacks it; for a fragment nothing stacks, only its entry
count MAY be reused.

#### Scenario: A file added outside the application
- **WHEN** a fragment file is created by another tool and the window is refreshed
- **THEN** the fragment is listed

#### Scenario: No store yet
- **WHEN** no store exists
- **THEN** the window says so and offers to create the first profile rather than reporting a failure

#### Scenario: A fragment changed outside the application
- **WHEN** a fragment file's bytes are changed by another tool and the window is refreshed
- **THEN** the entry counts, the resolved view and the layer rows reflect the changed bytes

#### Scenario: A fragment rewritten with the same bytes
- **WHEN** a fragment file is rewritten with byte-identical content and the window is refreshed
- **THEN** the window reads the file and presents the same result, whether or not it parsed the bytes again

#### Scenario: A large fragment no profile stacks
- **WHEN** the store holds a fragment of 100,000 entries that no profile stacks
- **THEN** its row states its entry count, and its parse is not held between reads

#### Scenario: A profile comes to stack it
- **WHEN** a profile is edited to stack that fragment
- **THEN** the next read parses it and the profile composes over it
