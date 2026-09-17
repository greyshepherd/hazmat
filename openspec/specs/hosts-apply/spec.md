# hosts-apply Specification

## Purpose

Applies a profile to the live hosts file: reads what is there now, notices when it
differs from the store, writes only the managed block, and can be undone.

## Requirements

### Requirement: The live file is read immediately before a planned write

An apply MUST read the current contents of the hosts file as the input to every
decision it makes, and MUST NOT act on a copy read earlier.

#### Scenario: The file changed since the last apply
- **WHEN** the hosts file was changed by another tool after the previous apply
- **THEN** the next apply reads the changed file and reports on what it found

#### Scenario: Reading needs no privilege
- **WHEN** an apply runs as an ordinary user
- **THEN** reading the hosts file succeeds without asking for privileged access

### Requirement: Drift is reported rather than silently overwritten

An apply MUST compare the block present in the live file against the block the
profile renders now, MUST report the difference, and MUST NOT replace a differing
block unless the caller names the block it expects to find there. An apply that
names no block MUST write only where the file holds none. An apply that names a
block MUST replace the live block only when it is byte-identical to the named
block, and MUST be refused when the file holds no block or a block that differs
from the named one.

#### Scenario: Block changed outside Hazmat
- **WHEN** the live file's block differs from the rendered block
- **THEN** the apply reports drift and leaves the file unchanged

#### Scenario: Drift overwritten deliberately
- **WHEN** the caller names the block it expects and the live block is byte-identical to it
- **THEN** the apply replaces the block and reports that it replaced the named block

#### Scenario: The expectation does not match
- **WHEN** the caller names a block and the live block differs from it
- **THEN** the apply is refused, reports drift, and leaves the file unchanged

#### Scenario: No block to replace
- **WHEN** the caller names a block and the live file holds none
- **THEN** the apply is refused and the file is unchanged

#### Scenario: First apply names nothing
- **WHEN** the caller names no block and the live file holds none
- **THEN** the block is installed and the outcome reports that it was installed

### Requirement: An apply changes bytes only inside the managed block

After an apply, every byte outside the block MUST be identical to the bytes that
were read, in the same order, with line endings, trailing whitespace, and
indentation intact.

#### Scenario: Vendor header and foreign entries
- **WHEN** a file holding the vendor header and entries written by other tools is applied
- **THEN** every byte outside the block is unchanged

### Requirement: The block's position is chosen per apply

The position at which the block lands MUST be a per-apply choice with a
documented default, so that its ordering relative to other entries can be decided
without changing the block format.

#### Scenario: Position chosen explicitly
- **WHEN** an apply names a position
- **THEN** the block lands there and every other line keeps its relative order

### Requirement: Planned bytes are verified before they replace the file

An apply MUST verify what it is about to write - that the bytes hold exactly one
well-formed block of a supported version, and that removing that block restores
the bytes that were read - and MUST leave the file unchanged when verification
fails.

#### Scenario: Verification fails
- **WHEN** the planned bytes do not hold exactly one well-formed block
- **THEN** the apply fails, reports why, and the file is unchanged

#### Scenario: Refused by the privileged side
- **WHEN** the privileged side refuses the write
- **THEN** the file is unchanged and the refusal reason is reported

### Requirement: An apply that changes nothing does not rewrite the file

An apply whose result would be the bytes already present MUST NOT replace the
file.

#### Scenario: The same profile applied twice
- **WHEN** the same profile is applied twice with no other change
- **THEN** the second apply reports that nothing needed to change and the file's modification time does not advance

### Requirement: Every apply reports an outcome

An apply MUST report one of: nothing to do, applied, refused, or failed, and MUST
name the cause for a refusal or a failure.

#### Scenario: Outcome of a change
- **WHEN** an apply replaces the block
- **THEN** the outcome reports that the file was changed

#### Scenario: Outcome of a refusal
- **WHEN** an apply is refused
- **THEN** the outcome names the reason it was refused

### Requirement: An applied block can be removed again

Removing the managed block from the live file MUST leave the bytes that were
outside it untouched, and MUST be a no-op when the file holds no block.

#### Scenario: Remove after apply
- **WHEN** a block applied to a file that had none is removed
- **THEN** the file is byte-identical to what it held before the apply

#### Scenario: Remove with no block present
- **WHEN** removal is requested for a file that holds no block
- **THEN** the file is unchanged
