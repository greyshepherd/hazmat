# Spec Delta

## MODIFIED Requirements

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
