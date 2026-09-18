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

### Requirement: With the window closed the application lives in the menu bar

Closing the window removes the application from the Dock and the application
switcher, the way menu-bar applications behave; the status item remains.
Opening a window puts the application back in both. The menu MUST offer opening
the window and quitting the application.

#### Scenario: The window closes
- **WHEN** the main window closes
- **THEN** the application is in neither the Dock nor the application switcher, and the status item remains

#### Scenario: The window opens again
- **WHEN** Open Hazmat is chosen from the menu
- **THEN** the window opens and the application is in the Dock and the application switcher again

### Requirement: The state is named from the reading, not remembered

The status item presents the mark and no text. The menu MUST mark the active
profile or profiles, MUST report drift when the live block matches no profile,
and the item's accessibility label MUST name the state, so reading the menu bar
still names what is live. What needs no attention says nothing: an applied
block, a file that is off, a healthy helper, and a successful write are all
silent.

#### Scenario: A profile is active
- **WHEN** a profile is active
- **THEN** the menu marks that profile and adds no line of its own

#### Scenario: Drift
- **WHEN** the live block matches no profile
- **THEN** the menu reports drift rather than naming a profile

#### Scenario: No block
- **WHEN** the live file holds no block
- **THEN** no profile is marked and the menu adds no line

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
- **THEN** nothing is written and the menu reports nothing

#### Scenario: Outcome is visible
- **WHEN** an activation fails
- **THEN** the menu reports what went wrong

### Requirement: A helper that needs attention is visible, and a refused switch is explained

The menu MUST report a helper that needs attention — not registered, awaiting
approval, or not answering — MUST offer registration when it is not enabled,
and an activation that the privileged side refuses MUST be reported with its
reason and MUST leave the file unchanged. An enabled helper is reported
nowhere.

#### Scenario: No approved helper
- **WHEN** a profile is activated while the helper is not approved
- **THEN** the menu reports that approval is needed and the file is unchanged

#### Scenario: Registration offered
- **WHEN** the helper is not registered
- **THEN** the menu offers to register it

#### Scenario: An enabled helper
- **WHEN** the helper is registered, approved, and answering
- **THEN** the menu reports nothing about it

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

### Requirement: The menu offers a manual update check when the bundle has a feed

The menu MUST offer to check for updates when the bundle declares a feed, MUST
NOT offer it when the bundle declares none, and MUST report a check that cannot
start — a feed that cannot be reached, or a release that fails verification — with
its reason rather than by failing silently. The application menu MUST offer the
same check, driven by the same presentation.

#### Scenario: A bundle with a feed
- **WHEN** the menu is opened in a release build
- **THEN** it offers to check for updates, and choosing it starts a check whose outcome the updater reports

#### Scenario: The application menu
- **WHEN** a bundle that declares a feed is running
- **THEN** the application menu offers the same check, and choosing it starts the same one

#### Scenario: A bundle without a feed
- **WHEN** the menu is opened in a development build that declares no feed
- **THEN** it offers no update check, in either the status item's menu or the application menu

#### Scenario: A check that cannot start
- **WHEN** the feed is unreachable or the release fails verification
- **THEN** the failure is reported with its reason
