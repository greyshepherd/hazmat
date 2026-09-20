# Spec Delta

## MODIFIED Requirements

### Requirement: Fragments are plain files

A fragment MUST be stored as an individual plain-text file containing host
entries in the `/etc/hosts` grammar: an address, a hostname, and optional
aliases, with blank lines and `#` comments permitted. A fragment MUST be usable
without modification by an external text editor or version control system.
Lines MUST be read the same whether they end in `\n` or `\r\n`; the line
ending is never part of an address or a name.

#### Scenario: Fragment edited outside the application
- **WHEN** a fragment file is modified by an external editor
- **THEN** the next composition uses the modified content with no import step

#### Scenario: Comments and blank lines are accepted
- **WHEN** a fragment contains comment lines, blank lines, and mixed tabs and spaces
- **THEN** composition succeeds and the comments contribute no entries

#### Scenario: A fragment saved with Windows line endings
- **WHEN** a fragment's lines end in `\r\n`
- **THEN** every line is parsed as it would be with `\n`, with the same entries and the same line numbers

#### Scenario: A fragment of a hundred thousand lines
- **WHEN** a fragment holds 100,000 well-formed lines
- **THEN** it parses to 100,000 entries with the same result a line-at-a-time reading would give
