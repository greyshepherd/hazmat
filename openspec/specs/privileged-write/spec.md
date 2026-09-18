# privileged-write Specification

## Purpose

Owns the privileged boundary: it takes finished bytes from the client, validates
them, and replaces the hosts file atomically with explicit ownership and no
access-control list, behind a helper the user approves once.

## Requirements

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
refuse requests from any other client. When the running daemon itself carries a
team identifier — that is, when it was signed for distribution — the requirement
it checks MUST anchor that team as well as the app's identifier, so that an
ad-hoc build of the same identifier cannot write. When the daemon carries no team
identifier, the requirement MUST be the app's identifier alone, so a development
build works without a certificate.

#### Scenario: Foreign client
- **WHEN** an unrelated process connects and requests a write
- **THEN** the request is refused and the file is unchanged

#### Scenario: A signed daemon and an ad-hoc client
- **WHEN** a daemon signed with a team identifier receives a request from a client of the same identifier that is signed ad-hoc
- **THEN** the request is refused and the file is unchanged

#### Scenario: A client from another team
- **WHEN** a daemon signed with a team identifier receives a request from a client signed by a different team
- **THEN** the request is refused and the file is unchanged

#### Scenario: A development daemon
- **WHEN** a daemon that carries no team identifier receives a request from the app built beside it
- **THEN** the request is accepted on the strength of the identifier both carry

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
not registered, awaiting approval, enabled, or not answering. A state of enabled
MUST mean the helper answered a presence check, not only that approval was
granted. A registration failure MUST be reported with its cause.

#### Scenario: Before approval
- **WHEN** the helper has been registered but not yet approved
- **THEN** its state reads as awaiting approval and no write can be performed

#### Scenario: After approval
- **WHEN** an administrator approves the helper and it answers a presence check
- **THEN** its state reads as enabled and a write can be performed

#### Scenario: Approved but not answering
- **WHEN** the helper is approved and does not answer a presence check
- **THEN** its state reads as not answering, no write is offered, and the state names the repair

#### Scenario: Approval denied or signature rejected
- **WHEN** approval is denied or the app's signature is not accepted
- **THEN** registration reports the cause and no write is possible

### Requirement: Presence is checked rather than assumed

The privileged side MUST answer a presence check that carries no request, and the
app MUST check presence rather than trusting the approval state. A presence check
MUST NOT carry a target path, a profile, or bytes to write, and MUST NOT read or
change the live file.

#### Scenario: The helper answers
- **WHEN** the app asks whether the helper is there
- **THEN** the helper answers, and the live file is neither read nor written

#### Scenario: Nothing answers
- **WHEN** the registered helper cannot be started and no reply arrives
- **THEN** the check reports that the helper is not answering

### Requirement: Installing and repairing make the helper answer and report what they found

The app MUST offer an install while no helper is registered and a repair while the
registered helper is not answering, and MUST run one bounded sequence for both: it
MUST register the helper, ask whether it answers, and, when the answer is that it
does not, MUST remove the registration and register again, repeating that for a
documented number of passes. It MUST NOT remove a registration before it has asked
whether the helper answers, because the removal is what leaves the system's record
for the helper disabled. It MUST ask a registration again while the system refuses
it because a removal has not finished, MUST stop asking when the refusal is one
that asking again cannot change, MUST report the outcome of the last step, and MUST
leave the live file untouched.

#### Scenario: Installing where nothing is registered
- **WHEN** the system reports no registered helper and the user installs it
- **THEN** the helper is registered, no registration is removed, and the state reports what the check found

#### Scenario: Repair of a helper that stopped being startable
- **WHEN** the registered helper is not answering and the user repairs it
- **THEN** the helper is asked first, and only a check that does not come back as an answer is followed by a removal and a registration

#### Scenario: Registration refused while the removal finishes
- **WHEN** the system refuses a registration because the removal has not finished
- **THEN** the sequence asks again, and the accepted registration is the one it checks

#### Scenario: The helper still does not answer
- **WHEN** no pass within the bound gets an answer
- **THEN** the outcome reports the last check, and no further pass is attempted

#### Scenario: Reporting what fails or is missing
- **WHEN** the removal, the registration, or the approval is what stops the sequence
- **THEN** the failure is reported with its cause and what the user can do about it, and the file is unchanged

### Requirement: A request that cannot be answered is reported within a bounded time

A request to the privileged side MUST be reported as failed within a documented
bound when no reply arrives, and the report MUST name what the user can do about
it. A write MUST NOT wait without an outcome.

#### Scenario: The helper never answers
- **WHEN** a write is requested and the helper does not answer
- **THEN** the write fails within the documented bound, the file is unchanged, and the report names the repair

#### Scenario: The helper answers
- **WHEN** a write is requested and the helper answers
- **THEN** the outcome is the helper's own answer and no bound is reached
