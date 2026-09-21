# Spec Delta

## MODIFIED Requirements

### Requirement: Fragment text is edited as text

The window MUST present the selected fragment as editable plain text, MUST save
it through the store's authoring operations, and MUST report a save that fails
with its reason while leaving the previous text in the file. Editing MUST stay
responsive when the fragment holds 100,000 or more lines: a keystroke MUST NOT
re-read, re-parse or re-lay out the whole fragment. A fragment that records an
origin MUST be presented read-only, naming the URL it is fetched from and
carrying the action that refreshes it, because a later refresh replaces its text.

#### Scenario: Round trip
- **WHEN** a fragment is edited and saved
- **THEN** the file holds the text that was saved and the next composition uses it

#### Scenario: The save is refused
- **WHEN** a save cannot be written
- **THEN** the reason is reported and the file keeps the text it had

#### Scenario: Typing in a large fragment
- **WHEN** a fragment of 100,000 lines is selected and a character is typed
- **THEN** the character appears without a stall, the fragment reads as unsaved, and the store is unchanged until Save

#### Scenario: A fragment that is fetched from a URL
- **WHEN** a fragment with a recorded origin is selected
- **THEN** its text is shown read-only with the URL it comes from, and the refresh action is offered beside it

## ADDED Requirements

### Requirement: Remote sources are managed from the window

The window MUST offer adding a source by name, URL, and interval, and changing a
source's URL and interval afterwards. The sidebar MUST mark a fragment that
records an origin and MUST show the state of its last refresh: when it last
succeeded, and the reason of the last failure when there was one. A source whose
interval has elapsed since its last successful refresh, or which has never been
refreshed, MUST be shown as out of date. Refreshing a source on demand MUST be
offered on that source's own row, and a refresh it asks for MUST report its
outcome the way an edit does.

#### Scenario: Adding a source
- **WHEN** a name, an HTTPS URL, and an interval are given for a new source
- **THEN** the source is recorded, listed, and asked to refresh, and its fragment appears once text is fetched

#### Scenario: The sidebar marks a source
- **WHEN** the store holds a fragment with a recorded origin
- **THEN** its row is marked as fetched from a URL and names when it last refreshed

#### Scenario: Out of date
- **WHEN** a source's interval has elapsed since its last successful refresh
- **THEN** its row shows that it is out of date, and a fetch that succeeds clears that state

#### Scenario: The last failure is visible
- **WHEN** a source's last refresh failed
- **THEN** its row reports the reason the refresh gave

#### Scenario: Refresh on demand
- **WHEN** the refresh action is used on a source's row
- **THEN** the source is fetched and the outcome is reported

#### Scenario: A URL that is refused
- **WHEN** a URL that is not HTTPS or a body that is refused is given
- **THEN** the reason is reported and no source state is left claiming a successful refresh
