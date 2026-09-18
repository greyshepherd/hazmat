# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: Colour carries the brand, and state is never colour alone`
- TO: `### Requirement: The window takes its colours from the system`

## MODIFIED Requirements

### Requirement: The window takes its colours from the system

The window MUST draw with the system's colours rather than a palette of its own:
surfaces, separators and the two text tiers MUST come from the system's semantic
colours, and the accent MUST be the one the user chose in System Settings,
applied to selections, focus rings and the filled control. The window MUST NOT
choose colours from the appearance it renders in. Every state MUST still be
carried by a glyph, a word and a colour together.

#### Scenario: The accent follows the user
- **WHEN** the accent colour is changed in System Settings
- **THEN** the window's selections, focus rings and filled control follow it

#### Scenario: The filled control
- **WHEN** the primary action is rendered
- **THEN** its label is drawn in the colour the system pairs with the accent fill

#### Scenario: The muted tier
- **WHEN** metadata is rendered below 18 points
- **THEN** it uses the secondary text tier rather than a colour reserved for detail at 18 points and above

#### Scenario: Status
- **WHEN** a write state or helper state is rendered
- **THEN** it carries a glyph and a word as well as a colour

#### Scenario: Dark appearance
- **WHEN** the system appearance is dark
- **THEN** the window renders in the system's dark surfaces and text tiers

## ADDED Requirements

### Requirement: The application runs one window

The application MUST have exactly one window instance. A command that needs the
window MUST bring the open window forward rather than opening another, and no
action MUST produce a second window, a second tab, or a second running instance.

#### Scenario: A command with the window open
- **WHEN** a command that asks the window for something is used while the window is open
- **THEN** the open window comes forward and the command proceeds there

#### Scenario: A command with the window closed
- **WHEN** that command is used with the window closed
- **THEN** the window opens and the command proceeds there

#### Scenario: New profile
- **WHEN** the new profile command is used
- **THEN** a profile is created in the store and no second window or tab appears

### Requirement: The window carries no control twice

The toolbar MUST NOT draw a control the split view already supplies. The sidebar
MUST have exactly one visible toggle, and the Window menu's Toggle Sidebar command
MUST leave the sidebar in the state that toggle shows.

#### Scenario: One toggle
- **WHEN** the window is shown
- **THEN** the title bar carries exactly one sidebar toggle in each state of the sidebar

#### Scenario: The menu and the toggle agree
- **WHEN** the sidebar is hidden with the Window menu's Toggle Sidebar command
- **THEN** the title bar's toggle shows the sidebar as hidden, and using it brings the sidebar back

### Requirement: The panes stay inside the window

The window MUST lay its panes out inside the window's frame whatever the store
and the selection hold. Content whose height cannot fit its column MUST NOT
enlarge the split view or move a pane outside the visible area.

#### Scenario: A first run
- **WHEN** no store exists and the window opens
- **THEN** the sidebar, the content pane and the detail pane are laid out inside the window's frame

#### Scenario: A profile with no layers
- **WHEN** a profile that stacks no layers is selected
- **THEN** the panes keep the window's height and the pane's content is readable

#### Scenario: Content taller than the pane
- **WHEN** a pane holds more content than the window has height for
- **THEN** the split view keeps the window's height rather than growing to the content
