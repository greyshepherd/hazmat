# app-bundle Specification

## Purpose
Assembles the application bundle the project ships: the layout it has, the
identity and version it reports, and the brand assets it carries.

## Requirements

### Requirement: The bundle is assembled around the build's executables

The assembler MUST take a finished build of the app and the daemon and lay them
out as one application bundle: both executables, the daemon's launchd property
list, embedded frameworks, and resources. It MUST refuse to assemble when either
executable is missing, and MUST leave no bundle behind when it refuses.

#### Scenario: Both executables present
- **WHEN** the assembler runs after a successful build
- **THEN** the bundle holds both executables, the daemon's property list, the embedded frameworks, and the resources

#### Scenario: A missing executable
- **WHEN** the build produced no daemon executable
- **THEN** the assembler refuses, reports which executable is missing, and writes no bundle

### Requirement: The bundle reports the identity the code declares

The bundle identifier, the daemon's label, its mach service name, and the
property list's file name MUST come from the single declaration in the code, so
the app, the daemon, and the bundle cannot disagree about them. The property list
MUST name the app executable, declare the bundle as an application, declare the
minimum system version the package targets, and be readable by the system's
property list tools.

#### Scenario: An assembled bundle
- **WHEN** a bundle is assembled
- **THEN** its identifier, daemon label, mach service, and property list file name equal the code's declarations

#### Scenario: The assembler's own view of the identity
- **WHEN** the assembler reports the identity it would write, without building
- **THEN** the reported values equal the code's declarations

### Requirement: The version has one source

The short version and the build number the bundle reports MUST come from one
checked-in release configuration, and neither executable MAY carry a second copy
of them. The build number MUST be a monotonically increasing integer, because the
update channel compares it numerically.

#### Scenario: A stamped bundle
- **WHEN** a bundle is assembled from a configuration naming version 1.2.3 and build 7
- **THEN** the bundle reports 1.2.3 as its short version and 7 as its build number

#### Scenario: No configuration
- **WHEN** a release is assembled with no release configuration
- **THEN** the assembly is refused before a bundle is written

### Requirement: The brand assets ship in the bundle

The app icon MUST be the exported ICNS, copied into the bundle's resources and
named by the property list, so Finder and the application switcher show the mark.
The menu bar image MUST ship as a one-times and two-times PNG pair under the name
the app looks it up by, MUST be a template image — one colour carried entirely by
its alpha channel, so the system can tint it — and the app MUST NOT recolour,
tint, or composite it.

#### Scenario: The icon is in the bundle
- **WHEN** a bundle is assembled
- **THEN** the icon the property list names exists in the resources and is a valid icon file

#### Scenario: The menu bar image stays a template
- **WHEN** the shipped menu bar images are inspected
- **THEN** every pixel that is visible carries no colour — its channels are equal, with the shape held in the alpha channel — at both sizes

### Requirement: The bundle is self-contained and runs without the toolchain

Every library either executable loads at run time MUST resolve inside the bundle
or to a system path, and the assembler MUST verify this and refuse an assembly
whose executable references a location outside the bundle. The bundle MUST launch
and serve the privileged interface on a machine with no Swift toolchain
installed.

#### Scenario: No library outside the bundle
- **WHEN** the assembled executables' library references are inspected
- **THEN** each one resolves either inside the bundle or to a system framework

#### Scenario: A reference outside the bundle
- **WHEN** an assembly would produce an executable that loads a library from outside the bundle
- **THEN** the assembly is refused

### Requirement: The development bundle and the release bundle are one shape

Both build shapes MUST come from the same assembler and MUST have the same
layout, the same identity, and the same version source. They MAY differ only in
their signature and in whether the bundle declares an update feed.

#### Scenario: The two shapes compared
- **WHEN** a development bundle and a release bundle are assembled from the same configuration
- **THEN** their file layouts are identical and their property lists differ only in the feed declaration

### Requirement: The embedded framework's licence text ships with it

The bundle MUST carry the licence text of every third-party framework it embeds,
and the release MUST refuse to assemble when that text is missing.

#### Scenario: The framework's licence
- **WHEN** a bundle embedding the update framework is assembled
- **THEN** the framework's licence text is present in the bundle's resources
