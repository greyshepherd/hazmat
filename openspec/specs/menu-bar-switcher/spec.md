# menu-bar-switcher Specification

## Purpose

Switches profiles and reports their state from the menu bar, so a profile can be
activated without opening the window and without guessing what the live file
currently holds.

## Requirements

### Requirement: A status item is present while the application runs

The application MUST present a status item in the menu bar whenever it is
running, and offering profile commands MUST NOT require the window to be open or
visible.

#### Scenario: Window closed
- **WHEN** the application runs with its window closed and a profile is activated from the menu bar
- **THEN** the profile is applied

### Requirement: The title names the state, not a remembered profile

The status item's title MUST name the active profile when one is active, MUST
report drift when the live block matches no profile, and MUST report that the
file is off when it holds no block.

#### Scenario: A profile is active
- **WHEN** a profile is active
- **THEN** the title names that profile

#### Scenario: Drift
- **WHEN** the live block matches no profile
- **THEN** the title reports drift rather than naming a profile

#### Scenario: No block
- **WHEN** the live file holds no block
- **THEN** the title reports that Hazmat is off

### Requirement: The menu lists the store's profiles as they are now

Opening the menu MUST read the store and the live file at that moment, MUST list
the profiles the store holds with the active ones marked, and MUST NOT present a
cached list.

#### Scenario: A profile added since the last look
- **WHEN** a profile file is created in the store and the menu is opened
- **THEN** the new profile appears in the menu

#### Scenario: Empty or missing store
- **WHEN** the store holds no profiles or does not exist
- **THEN** the menu says so and offers no activation

### Requirement: Activation goes through the existing apply path

Activating a profile from the menu MUST apply the same rendered block the
window applies, and MUST inherit the guarantees of an apply: verification before
the write, atomic replacement, and a reported outcome.

#### Scenario: Nothing to do
- **WHEN** the active profile is activated again
- **THEN** the outcome reports that nothing needed to change

#### Scenario: Outcome is visible
- **WHEN** an activation changes the file
- **THEN** the menu reports that the file was changed

### Requirement: Helper state is visible and a refused switch is explained

The menu MUST report whether the privileged helper is not registered, awaiting
approval, or enabled, MUST offer registration when it is not enabled, and an
activation that the privileged side refuses MUST be reported with its reason and
MUST leave the file unchanged.

#### Scenario: No approved helper
- **WHEN** a profile is activated while the helper is not approved
- **THEN** the menu reports that approval is needed and the file is unchanged

#### Scenario: Registration offered
- **WHEN** the helper is not registered
- **THEN** the menu offers to register it

### Requirement: Drift is never overwritten silently

When the live block matches no profile, activating a profile MUST NOT replace the
block, and the menu MUST offer the overwrite as its own deliberate item naming
what it will replace.

#### Scenario: Switch over a drifted block
- **WHEN** a profile is activated while the live block has been edited outside the application
- **THEN** the file is left as it is and the menu reports drift

#### Scenario: Overwrite chosen
- **WHEN** the deliberate overwrite is chosen for a drifted block
- **THEN** the block is replaced and the outcome reports that drift was overwritten

### Requirement: Off removes the block

The menu MUST offer an item that removes the managed block, and choosing it when
the file holds no block MUST be reported as nothing to do rather than as a
failure.

#### Scenario: Turning off
- **WHEN** Off is chosen while a block is present
- **THEN** the block is removed and the bytes outside it are untouched

#### Scenario: Already off
- **WHEN** Off is chosen while no block is present
- **THEN** the outcome reports that nothing needed to change

### Requirement: Failures are reported in the menu

A read failure, a malformed block, a refused write, or a failed write MUST be
reported with a reason the user can see, and MUST leave the file unchanged.

#### Scenario: The file cannot be read
- **WHEN** the live file cannot be read
- **THEN** the menu reports the failure with its reason in place of the active profile
