# Spec Delta

## MODIFIED Requirements

### Requirement: The menu lists the store's profiles as they are now

Opening the menu MUST read the store and the live file at that moment, MUST list
the profiles the store holds with the active ones marked, and MUST NOT present a
cached list. Deriving the marks from a large store MUST NOT stall the menu:
when the derivation is not immediate, the menu MUST open with the profiles
listed and the marks it last derived, and MUST show the marks from this
reading as soon as they are derived, without being closed and reopened.

#### Scenario: A profile added since the last look
- **WHEN** a profile file is created in the store and the menu is opened
- **THEN** the new profile appears in the menu

#### Scenario: Empty or missing store
- **WHEN** the store holds no profiles or does not exist
- **THEN** the menu says so and offers no activation

#### Scenario: A store with a hundred thousand entries
- **WHEN** the store's profiles stack a fragment of 100,000 entries and the menu is opened
- **THEN** the menu opens without a stall, and the marks reflect the live file as read on this opening

#### Scenario: A fragment changed since the last look
- **WHEN** a fragment file the active profile stacks is changed by another tool and the menu is opened
- **THEN** the marks reflect the changed fragment, not the previous reading
