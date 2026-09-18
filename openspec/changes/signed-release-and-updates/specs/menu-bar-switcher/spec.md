# Spec Delta

## MODIFIED Requirements

### Requirement: The title names the state, not a remembered profile

The status item's title MUST name the active profile when one is active, MUST
report drift when the live block matches no profile, and MUST report that the
file is off when it holds no block. The status item MUST show the project's mark
beside that title, taken from the application bundle, and the mark MUST remain a
template image the system tints rather than an image the app colours. When the
mark is missing from the bundle, the title alone MUST be shown and the item MUST
stay usable.

#### Scenario: A profile is active
- **WHEN** a profile is active
- **THEN** the title names that profile

#### Scenario: Drift
- **WHEN** the live block matches no profile
- **THEN** the title reports drift rather than naming a profile

#### Scenario: No block
- **WHEN** the live file holds no block
- **THEN** the title reports that Hazmat is off

#### Scenario: The mark beside the title
- **WHEN** the application is running with the mark present in its bundle
- **THEN** the status item shows the mark beside the state title

#### Scenario: No mark in the bundle
- **WHEN** the bundle carries no menu bar image
- **THEN** the status item shows the state title alone and the menu still opens

## ADDED Requirements

### Requirement: The menu offers a manual update check when the bundle has a feed

The menu MUST offer to check for updates when the bundle declares a feed, MUST
NOT offer it when the bundle declares none, and MUST report a check that cannot
start — a feed that cannot be reached, or a release that fails verification — with
its reason rather than by failing silently.

#### Scenario: A bundle with a feed
- **WHEN** the menu is opened in a release build
- **THEN** it offers to check for updates, and choosing it starts a check whose outcome the updater reports

#### Scenario: A bundle without a feed
- **WHEN** the menu is opened in a development build that declares no feed
- **THEN** it offers no update check

#### Scenario: A check that cannot start
- **WHEN** the feed is unreachable or the release fails verification
- **THEN** the failure is reported with its reason
