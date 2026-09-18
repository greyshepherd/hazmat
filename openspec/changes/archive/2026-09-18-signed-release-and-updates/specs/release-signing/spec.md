# Spec Delta

## Purpose

Turns the assembled bundle into something a second person can install: signed
with a Developer ID under the hardened runtime, notarized, stapled, and verified
before anything is published.

## ADDED Requirements

### Requirement: Every nested executable is signed inside out under the hardened runtime

The release MUST sign the embedded framework's helper executables and services,
then the framework, then the daemon with its own identifier, then the app, each
with a secure timestamp and the hardened runtime, and MUST NOT sign with a
recursive or deep signing option. The bundle's seal MUST be valid after signing.

#### Scenario: Nested code is signed
- **WHEN** a signed release bundle is verified strictly, including nested code
- **THEN** the framework, its services and helpers, the daemon, and the app all carry a valid signature from the release identity

#### Scenario: Signed inside out
- **WHEN** the app is signed before the code it embeds
- **THEN** the nested signature that follows invalidates the app's seal and the release reports a failed verification

### Requirement: The signing identity and the privileged requirement name one team

The release MUST sign with an identity whose team identifier equals the team the
privileged side requires, and MUST refuse to sign when the identity is missing,
when the identity names no team, or when the two disagree.

#### Scenario: A matching identity
- **WHEN** the release signs with an identity issued to the team the daemon requires
- **THEN** the signing succeeds and the daemon's requirement holds for the signed app

#### Scenario: A mismatched identity
- **WHEN** the only available identity belongs to another team
- **THEN** the release refuses before signing and reports both team identifiers

### Requirement: The distributable is a disk image holding a stapled app

A release MUST produce a disk image containing the app and a link to the
applications folder, MUST staple the app's notarization ticket before the image is
built, and MUST notarize and staple the image itself, so the app installs and
runs on a machine that first sees it offline.

#### Scenario: The image and its contents
- **WHEN** a release image is opened
- **THEN** it holds the app beside a link to the applications folder, and the app inside carries a stapled ticket

#### Scenario: Assessed by the system
- **WHEN** the mounted image and the app inside it are assessed by the system's own assessment tool
- **THEN** both are accepted for distribution

### Requirement: Notarization is a gate rather than a step

A release MUST NOT publish, and MUST NOT report success for, an artifact that has
not been accepted by the notarization service and stapled. When notarization
fails, the release MUST report the submission identifier and the service's reason
and MUST leave the artifact unpublished.

#### Scenario: A failed notarization
- **WHEN** the notarization service rejects the submission
- **THEN** the release reports the submission identifier and the reason, and nothing is published

#### Scenario: An unstapled artifact
- **WHEN** an artifact has no stapled ticket
- **THEN** the release refuses to publish it

### Requirement: Verification runs before publication

Before a release publishes anything, it MUST verify the signatures strictly,
validate that the ticket is stapled, assess the image for distribution, and
confirm the version the artifacts report equals the version the release was told
to build. A failed verification MUST stop the release.

#### Scenario: A verified release
- **WHEN** every verification passes
- **THEN** the release proceeds to publish the image and the feed

#### Scenario: A wrong version
- **WHEN** the built app reports a version other than the one the release was asked for
- **THEN** the release stops and nothing is published

### Requirement: A release runs unattended

The release MUST take its identity, its notarization credentials, and its storage
credentials from the environment, MUST NOT prompt for input, and MUST report a
missing credential as the reason it stopped.

#### Scenario: Credentials from the environment
- **WHEN** a release runs with every credential present in the environment
- **THEN** it completes without any interactive prompt

#### Scenario: A missing credential
- **WHEN** a notarization credential is absent
- **THEN** the release stops before submitting anything and names the credential that is missing
