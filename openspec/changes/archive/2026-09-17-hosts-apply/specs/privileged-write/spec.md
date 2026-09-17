# Spec Delta

## Purpose

Owns the privileged boundary: it takes finished bytes from the client, validates
them, and replaces the hosts file atomically with explicit ownership and no
access-control list, behind a helper the user approves once.

## ADDED Requirements

### Requirement: The privileged side takes finished bytes and nothing else

A write request MUST carry the complete bytes to write and MUST NOT carry a
target path. The privileged side MUST NOT compose, parse, or resolve host
entries, and MUST NOT invoke a shell or any external program to perform the
write.

#### Scenario: Request carries bytes only
- **WHEN** a write request arrives
- **THEN** the target is the hosts file and the caller has no way to name another path

#### Scenario: No external process
- **WHEN** a write is performed
- **THEN** no shell and no external program is executed

### Requirement: Bytes are validated before anything is written

A request MUST be refused unless the bytes hold exactly one well-formed managed
block of a supported version, and MUST be refused when the bytes exceed a
documented size bound. Nothing is written when a request is refused.

#### Scenario: Malformed or foreign content
- **WHEN** the bytes hold no block, more than one block, a malformed marker, or an unsupported version
- **THEN** the request is refused with a reason and the file is unchanged

#### Scenario: Oversized request
- **WHEN** the bytes exceed the size bound
- **THEN** the request is refused and the file is unchanged

### Requirement: The write is atomic

The file MUST be replaced in a single step, so that a reader sees either the
previous contents or the new contents and never a partial file, and an
interruption MUST leave the previous contents in place.

#### Scenario: Interrupted write
- **WHEN** a write is interrupted before it completes
- **THEN** the file still holds its previous contents

#### Scenario: Reader during a write
- **WHEN** the file is read while a write is in progress
- **THEN** the reader sees one of the two complete contents

### Requirement: The written file is a regular file with explicit ownership and no access-control list

After a write the file MUST be a regular file, MUST be owned by the system
account with the documented group and mode, and MUST NOT carry an access-control
list that restricts other writers. The write MUST NOT replace the file with a
symbolic link.

#### Scenario: Attributes after a write
- **WHEN** a write completes
- **THEN** the file is a regular file whose owner, group, and mode are the documented values and no restricting access-control list is present

#### Scenario: Other tools can still write
- **WHEN** another tool edits the file after an apply
- **THEN** the edit is permitted

### Requirement: A write is accepted only from the app that registered the helper

The privileged side MUST verify that a request comes from its own app, and MUST
refuse requests from any other client.

#### Scenario: Foreign client
- **WHEN** an unrelated process connects and requests a write
- **THEN** the request is refused and the file is unchanged

### Requirement: A write is applied only to the file the client planned from

A request MUST carry the state of the file that the bytes were planned from, and
the privileged side MUST refuse the write when the file no longer matches that
state, so that a change made between planning and writing is never lost.

#### Scenario: The file changed between planning and writing
- **WHEN** the hosts file is modified after the client read it and before the write is performed
- **THEN** the write is refused, the reason is reported, and the file keeps that modification

#### Scenario: The file still matches
- **WHEN** the hosts file still matches the state the client planned from
- **THEN** the write is performed

### Requirement: Registration needs one approval and its state is visible

The helper MUST be registered as a daemon by its app, MUST require a single
administrative approval before it can write, and MUST expose its state as one of:
not registered, awaiting approval, or enabled. A registration failure MUST be
reported with its cause.

#### Scenario: Before approval
- **WHEN** the helper has been registered but not yet approved
- **THEN** its state reads as awaiting approval and no write can be performed

#### Scenario: After approval
- **WHEN** an administrator approves the helper
- **THEN** its state reads as enabled and a write can be performed

#### Scenario: Approval denied or signature rejected
- **WHEN** approval is denied or the app's signature is not accepted
- **THEN** registration reports the cause and no write is possible
