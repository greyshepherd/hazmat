# update-channel Specification

## Purpose
Carries releases to people who already have the app: where the feed lives, what
an archive proves about itself, what the feed says about a release, how the app
checks, and in what order a release becomes visible.

## Requirements

### Requirement: The feed has one stable address over HTTPS

The bundle MUST declare its feed address in the property list, the address MUST
be an absolute HTTPS address, and it MUST come from the release configuration so
that a release and the app it produces cannot name different feeds. A bundle that
declares no feed MUST NOT be able to check for updates.

#### Scenario: A release bundle
- **WHEN** a release bundle is assembled from a configuration naming a feed
- **THEN** the bundle's property list declares that address and the app checks that feed

#### Scenario: A development bundle
- **WHEN** a development bundle declares no feed
- **THEN** the app offers no update check and makes no request to any feed

### Requirement: Every published archive carries a signature the app verifies

Each published archive MUST carry an EdDSA signature over the archive's bytes, the
bundle MUST declare the public key that verifies it, and an archive whose
signature does not verify against that key MUST NOT be installed, offered, or
extracted.

#### Scenario: A signed archive
- **WHEN** an archive signed with the release key is offered to the app
- **THEN** the app verifies it against the key in its own bundle and proceeds

#### Scenario: A tampered or foreign archive
- **WHEN** an archive's bytes do not match its signature, or it was signed by another key
- **THEN** the app refuses the update and reports the failure

### Requirement: The feed states everything the app needs to decide

Each entry in the feed MUST state the build number the app compares, the short
version a person reads, the archive's address and byte length, the archive's
signature, the publication time, the minimum system version the release requires,
and that Apple silicon is required. A release MUST carry release notes the entry
links to.

#### Scenario: An entry for a release
- **WHEN** a released version is read from the feed
- **THEN** the entry states its build number, short version, archive address and length, signature, publication time, minimum system version, and Apple silicon requirement

#### Scenario: An entry missing a required statement
- **WHEN** a published entry omits the signature or the archive's length
- **THEN** the app treats the entry as unusable and reports the failure rather than installing it

### Requirement: The app checks on a schedule and on request

The app MUST check the feed automatically unless the user has turned automatic
checks off, and MUST be able to start a check on request. An update MUST NOT be
installed without the user agreeing to it.

#### Scenario: An automatic check
- **WHEN** the app runs with automatic checks left on
- **THEN** it checks the feed on its own schedule without being asked

#### Scenario: An update found
- **WHEN** a check finds a newer build
- **THEN** the app offers it and installs it only after the user agrees

### Requirement: A release becomes visible in one order and once

A release MUST publish its archive before it publishes the feed entry that names
it, MUST refuse a build number that is not greater than the greatest build number
already published, and MUST NOT publish an entry naming an archive that is not
already readable at its address.

#### Scenario: Publishing a release
- **WHEN** a release is published
- **THEN** the archive is readable at its address before the feed naming it is readable

#### Scenario: A build number already published
- **WHEN** a release is asked to publish a build number that the feed already carries, or a smaller one
- **THEN** the release refuses and leaves the feed as it was

#### Scenario: An archive that is not there
- **WHEN** a publish finds the archive missing at its address
- **THEN** it refuses to publish the feed entry naming it

### Requirement: The feed is fresh and archives are immutable

The feed MUST be served with a cache lifetime short enough that a new release is
visible within the hour, and a published archive MUST be immutable at its address,
so that two people checking within the same hour cannot receive different answers.

#### Scenario: Cache lifetimes as served
- **WHEN** the served headers for the feed and for an archive are inspected
- **THEN** the feed's lifetime is an hour or less and the archive's address is stable across releases

### Requirement: An update leaves what the app owns alone

An update MUST replace only the application bundle. The store, the live hosts file
and the privileged boundary MUST be unaffected by it, and after an update the app
MUST still be able to apply and remove a block through the approved helper.

#### Scenario: After an update
- **WHEN** the app updates itself and is relaunched
- **THEN** the store and the live block are as they were, and an apply through the privileged side still succeeds

#### Scenario: The replaced daemon
- **WHEN** an update replaces the bundle holding the daemon
- **THEN** the daemon that serves the next request is the updated one and its requirement still holds for the app

### Requirement: The privileged side does not outlive the build that installed it

The daemon MUST stop serving after a bounded period with no open connection, so
that a replaced build cannot keep answering requests, and after an update the next
request MUST be served by the build that is installed. A request that arrives as
the daemon stops MUST be answered by the daemon that starts in its place, or
attempted again by the client, rather than failing.

#### Scenario: Idle after serving
- **WHEN** the daemon answers a request and no further connection arrives for the documented period
- **THEN** the process stops, and the next request is served by a process started from the installed bundle

#### Scenario: A request during the stop
- **WHEN** a request arrives while the daemon is stopping
- **THEN** the request is answered by the restarted daemon and the file is written as asked
