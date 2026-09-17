# hosts-block Specification

## Purpose

Renders a resolved entry set into a delimited block and replaces only that block
within an existing hosts file, leaving every other byte untouched.

## Requirements

### Requirement: The managed block is delimited by identifiable markers

A rendered block MUST begin with a start marker and end with an end marker. The
start marker MUST identify the content as Hazmat-managed and MUST carry a format
version so that a future format change can be recognised rather than
misinterpreted. The markers MUST be distinguishable from ordinary host entries
and comments.

#### Scenario: Block is recognised in a file
- **WHEN** a hosts file contains a Hazmat-managed block
- **THEN** the block's boundaries are located without relying on line numbers

#### Scenario: Format version is available
- **WHEN** a block written by an older format is read
- **THEN** the version it was written with is reported

### Requirement: Rendered output is byte-stable

For an identical resolved entry set and identical surrounding content, rendering
MUST produce identical bytes. Entry order within the block MUST be defined by
the renderer rather than inherited from filesystem enumeration, and the block
MUST use one documented line ending and terminate with a newline.

#### Scenario: Repeated rendering is identical
- **WHEN** the same resolved set is rendered twice
- **THEN** the two outputs are byte-identical

#### Scenario: No trailing-newline drift
- **WHEN** a rendered block is spliced and then read back
- **THEN** the content between the markers matches the rendered bytes exactly

### Requirement: Content outside the managed block is preserved exactly

Every byte outside the markers MUST be preserved, including comments, blank
lines, indentation, trailing whitespace, and line endings. Existing lines MUST
retain their relative order. The renderer MUST NOT normalise, reorder, or
reformat content it does not own.

#### Scenario: Distribution file header survives
- **WHEN** a hosts file contains the vendor-supplied header and loopback entries annotated "Do not change this entry"
- **THEN** those lines are byte-identical after splicing

#### Scenario: Foreign entries are untouched
- **WHEN** the file contains entries written by another tool
- **THEN** those entries are byte-identical after splicing

### Requirement: A file holds at most one managed block

A hosts file MUST contain no more than one Hazmat-managed block. A file
containing multiple blocks, an unterminated block, or a malformed marker MUST be
reported as an error and MUST NOT be modified.

#### Scenario: Duplicate blocks are refused
- **WHEN** a file contains two managed blocks
- **THEN** splicing fails with an error and the input is left unchanged

#### Scenario: Unterminated block is refused
- **WHEN** a start marker has no matching end marker
- **THEN** splicing fails with an error and the input is left unchanged

### Requirement: Splicing is idempotent

Splicing a block into a file that already contains that block MUST produce an
identical file. Applying the same render twice MUST NOT duplicate the block or
alter the file further.

#### Scenario: Re-applying changes nothing
- **WHEN** a rendered block is spliced into a file that already contains it
- **THEN** the resulting bytes equal the input bytes

### Requirement: Removing the block restores the original file

The block MUST be removable. Removing a block from a spliced file MUST restore
exactly the bytes that were present before the splice, including any separator
introduced by the splice itself.

#### Scenario: Round trip through splice and removal
- **WHEN** a block is spliced and then removed
- **THEN** the result is byte-identical to the pre-splice file

### Requirement: An empty resolved set still renders a block

A profile with no resolved entries MUST render a block containing its markers
and no entries. An empty block MUST be distinguishable from an unmanaged file,
so that an active-but-empty profile is not mistaken for an inactive one.

#### Scenario: Empty profile renders markers only
- **WHEN** a profile resolves to no entries
- **THEN** the block is present, contains no entries, and is removable by the same process
