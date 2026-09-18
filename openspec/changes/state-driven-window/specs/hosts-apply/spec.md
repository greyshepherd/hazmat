# Spec Delta

## ADDED Requirements

### Requirement: A block an apply replaced is kept so the change can be reverted

An apply that replaces a block MUST keep the block it replaced for the running
application. Restoring that block MUST be performed as an apply that replaces the
block the apply wrote, MUST be refused with its reason when the live block is no
longer that block, and MUST leave the file and every byte outside the block
untouched. An apply that installed a block where the file held none MUST be
revertible by removing it. No restore MUST be offered when the running
application has not applied anything.

#### Scenario: Reverting a replacement
- **WHEN** the revert is chosen after an apply that replaced a block
- **THEN** the live file holds the block that apply replaced, byte for byte

#### Scenario: Reverting an install
- **WHEN** the revert is chosen after an apply that installed a block into a file that held none
- **THEN** the block is removed and the file holds the bytes it held before the apply

#### Scenario: The file changed before the revert
- **WHEN** the live block is no longer the block the apply wrote
- **THEN** the revert is refused with its reason and the file is unchanged

#### Scenario: Nothing to revert
- **WHEN** no apply has been performed by the running application
- **THEN** no revert is offered

#### Scenario: Reverting needs the same guarantees as an apply
- **WHEN** a revert runs while the helper is not enabled
- **THEN** the revert is refused with the privileged reason and the file is unchanged
