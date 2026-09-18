# Spec Delta

## ADDED Requirements

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
