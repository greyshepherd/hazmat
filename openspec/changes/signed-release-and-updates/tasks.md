# Tasks

## 1. The assets and the release configuration

- [x] 1.1 Commit the brand assets under `Assets/`: the ICNS, the menu bar PNG pair, the SVG sources they were exported from, and the export's README and manifest. Verify with `file` and `sips` that the icon is a valid icon file and the menu bar images are 22 and 44 px
- [x] 1.2 Add the release configuration: short version, build number, feed address, the repository a release publishes to and its tag prefix, the path the feed is written to, and the update public key. Verify it parses as JSON, that the values are the only place they appear, and that a release with the feed absent is refused
- [x] 1.3 Add the embedded framework's licence text beside the assets, with a comment naming the version it came from. Verify the bundle carries it and the release refuses to assemble without it
- [x] 1.4 Add a test that decodes both menu bar images and asserts every pixel is either fully transparent or opaque black, and that the icon the property list names exists in the bundle's resources. Verify the test fails when a colour is introduced into a copy of the image

## 2. The bundle assembler

- [x] 2.1 Write the assembler replacing the development script: it takes a configuration and a signing mode, lays out the bundle, stamps the property lists from the release configuration and the code's identity declaration, copies the resources including the framework, and refuses an incomplete assembly. Verify a debug bundle and a release bundle both assemble and their file lists match
- [x] 2.2 Give the assembler a mode that reports the identity and version it would write without building. Verify a test compares that output with the identity the code declares, and that the test fails when either side is edited alone
- [x] 2.3 Verify the bundle is self-contained: the assembled executables' library references resolve inside the bundle or to a system path, and the assembler refuses an assembly that would reference anything else. Verify by inspecting both executables and by making the check fail deliberately
- [x] 2.4 Verify the daemon's property list is lint-valid and names the label, the executable, and the mach service the code declares, and that the app registering it reads a state other than not-found when the bundle is assembled. Verify by linting the file and by running the assembled app and reading the helper state in the window
- [ ] 2.5 Verify the development shape is unchanged in behaviour: run the app from an assembled debug bundle and confirm the window, the status item's menu, and an apply all work as they did before, with the existing test suite passing

## 3. The mark in the status item

- [x] 3.1 Load the menu bar template from the main bundle, set it as a template image, and place it beside the state title. Verify the status item shows both in a running build, and that a bundle with the image removed still shows a usable item with the title alone
- [x] 3.2 Check the combined image and title against the running menu bar rather than against the documentation, in a dark and a light appearance. If the platform renders only one of the two, move the status item to an AppKit status item that sets the image and the title directly, fed by the same presentation
- [x] 3.3 Update the isolation tests that assert what the entry point contains, and add a guard that the app never recolours or untemplates the mark. Verify the suite passes and that a deliberate tint in a copy of the scene is caught

## 4. The update channel in the app

- [x] 4.1 Add the update framework as a dependency of the app target only. Verify the core, protocol, privileged, and app-support targets still build and pass their purity and isolation tests without it
- [x] 4.2 Declare the update-checking protocol in app support, carry the check as an item in the menu presentation that is present only when the bundle declares a feed, and forward the choice from the model. Verify tests cover: a bundle with a feed offers the check; a bundle without one does not; a refused check is reported with its reason
- [x] 4.3 Implement the adapter in the app on the framework's standard controller, reading the feed and the public key from the bundle. Verify a release bundle's property list declares both and a debug bundle declares neither, and that the app launches with the framework embedded
- [ ] 4.4 Verify a manual check runs from the menu against a test feed and reports its outcome, and that a check whose feed is unreachable reports a failure with a reason rather than failing silently
- [ ] 4.5 Offer the check in the application menu as well, driven by the same presentation, and verify it is absent or disabled in a bundle that declares no feed

## 5. The daemon's requirement and its lifetime

- [x] 5.1 Derive the verification requirement from the daemon's own signature: team-anchored when the running binary carries a team identifier, identifier-only when it does not. Verify tests assert both requirement strings, that an ad-hoc client is refused by a team-anchored daemon, and that a client from another team is refused
- [ ] 5.2 Have the daemon count open connections and stop after the documented idle period with none. Verify a test of the idle rule, and a supervised check that the process is gone after the period and that the next request is served by a newly started process from the installed bundle
- [ ] 5.3 Attempt a request once more when the connection dies before a reply, so a request that lands while the daemon stops is answered by its replacement. Verify a test in which the first attempt fails and the second succeeds, and a supervised check that an apply during the stop writes the file and reports success
- [x] 5.4 Verify the release refuses to sign when the identity's team differs from the team the configuration names, reporting both

## 6. Signing, notarization, and the disk image

- [ ] 6.1 Sign the release bundle inside out — the framework's services and helpers, the framework, the daemon with its own identifier, then the app — with a secure timestamp and the hardened runtime, without a deep or recursive flag. Verify a strict verification including nested code passes and that every nested item reports the release identity
- [ ] 6.2 Build the disk image holding the app and a link to the applications folder, staple the app before building, notarize and staple the image. Verify the system's assessment accepts the image and the app, and that the ticket validates with no network
- [ ] 6.3 Orchestrate the release so that it verifies the artifacts, refuses a wrong version, and stops on a missing identity, a missing notarization credential, or a failed notarization, naming the submission and the reason. Verify each refusal by running the release without that input
- [ ] 6.4 Verify the image installs on an account that has never seen the app: Gatekeeper accepts it, the app launches, the helper can be registered from where the app is installed, and the helper's state reads as answering rather than only as approved

## 7. The feed and its key

- [ ] 7.1 Generate the update signing key once with the pinned distribution's tool, record the public key in the release configuration, and confirm the private key is not in the repository. Verify with a repository-wide search and by listing the keychain item
- [ ] 7.2 Pin the distribution's version and checksum in the release tooling and verify the download against it. Verify a tampered download is refused before any tool runs
- [ ] 7.3 Generate the feed entry for a release archive. Verify the entry states the build number, short version, archive address and length, signature, publication time, minimum system version, and the Apple silicon requirement, and that it links release notes
- [ ] 7.4 Verify the ordering rules: an archive is readable at its published address before any entry naming it, and a build number that is not greater than the published maximum is refused, leaving the feed unchanged

## 8. Publishing

- [ ] 8.1 Write the publish step: create the release, upload the disk image to it, then write the feed and push it, with the repository, the tag prefix and the feed's path read from the release configuration and the token from the environment. Verify the archive answers at its release address before the feed naming it is readable, and measure the lifetime the feed is served with rather than assuming it
- [ ] 8.2 Verify the publish step reads the published feed first and refuses a build number equal to or smaller than the published maximum
- [ ] 8.3 Verify a publish with no token stops before uploading and names what is missing
- [ ] 8.4 Enable Pages for the repository from the branch and directory the configuration names, and verify the feed's address answers over HTTPS with the published file

## 9. Acceptance against a real upgrade

- [ ] 9.1 Install 1.0 from the disk image, register and approve the helper from that location, confirm its state reads as answering, and apply a profile. Cut 1.1, upgrade from the app's own menu, and verify the app reports 1.1, the store and the live block are untouched, an apply through the helper still succeeds, and the daemon that answers is the updated build
- [ ] 9.2 Verify a tampered archive is refused: alter one byte of a published image and confirm the app refuses the update and reports a signature failure
- [ ] 9.3 Verify the installed build's status item shows the mark beside the state title in both menu bar appearances, and that switching a profile from the menu still works after the upgrade

## 10. Documentation and the guard

- [ ] 10.1 Rescope the isolation guard: no packaging, signing, or update vocabulary in the core, protocol, privileged, or app-support targets, and the update framework's name only in the adapter that implements the update protocol. Verify the suite passes and that a deliberate violation in each guarded target is caught
- [ ] 10.2 Update the README: the status, how to build and run a development bundle, how to cut a release, the feed address, and how the signing key is stored and backed up. Verify a reader can follow it to assemble a development bundle and to start a release
- [ ] 10.3 Document the one-time setup a first release needs — notarization credentials, key generation and backup, the repository being public, Pages being enabled on the branch and directory the configuration names, and the credentials the publish step reads — and walk the sequence once against a throwaway version to confirm the steps are complete. Note that the helper's registration names the bundle it was registered from, so an app that has moved has to be registered again from where it now lives
