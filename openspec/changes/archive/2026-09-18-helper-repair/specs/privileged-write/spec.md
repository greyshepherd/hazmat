# Spec Delta

## MODIFIED Requirements

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

## ADDED Requirements

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
