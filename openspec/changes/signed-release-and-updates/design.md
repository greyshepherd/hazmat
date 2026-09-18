# Design

## Context

- The package builds two executables with SwiftPM and nothing else. The only way
  to run the app is a hand-built bundle, because `SMAppService` registers a daemon
  out of a signed bundle; the current script assembles that bundle, writes a bare
  property list, and signs ad-hoc.
- Identity is declared once, in the protocol target, and the assembler repeats the
  values as shell variables. The daemon verifies a client with the identifier-only
  requirement; a team-anchored requirement is written and tested but unused.
- The daemon runs until it is signalled or the machine restarts: it has no idle
  exit, and its launchd property list sets no keep-alive.
- The app is arm64-only, targets macOS 15, and the status item's content is a
  state title built by app support.
- The brand export provides an ICNS built from the light tile and a 22/44 px pure
  black-plus-alpha menu bar template.
- A Developer ID Application identity is in the keychain and `notarytool` is
  installed; no notary credentials are stored, and nothing in the repository
  builds, signs, notarizes, or publishes today.

## Goals / Non-Goals

**Goals:**

- One assembler that produces both the bundle a developer runs and the bundle a
  release ships, so the release path is exercised on every day of development.
- A bundle that declares its version and feed from one checked-in configuration,
  carries the mark, and refuses to be assembled half-formed.
- A release that cannot publish anything it has not signed, notarized, stapled,
  and verified, and cannot publish a build number that users would not see.
- An update channel whose trust anchor is a signing key that never enters the
  repository, and whose failure modes are reported rather than silent.
- The privileged boundary tightening exactly when the build is signed to be
  distributed, with no build flag that can be set wrongly.

**Non-Goals:**

- A sandboxed build; the app writes through a launchd daemon by design.
- Intel or universal binaries; the project is arm64 by charter.
- Delta updates, a beta channel, staged rollout, and DMG window styling. All are
  additive to a feed that exists, and none is needed for the first release.
- Wiring the release into CI. The scripts take their inputs from the environment
  and prompt for nothing, so a runner is a wrapper around them rather than a
  rewrite.

## Decisions

**1. The brand assets live in the repository, restricted to what ships.** An
`Assets/` directory at the root holds the ICNS, the menu bar PNG pair, the SVG
sources those were exported from, and the export's README and manifest for
provenance. The derived PNG farms and the wordmark font stay out: nothing refers
to them, and the font would carry an OFL obligation for a file the bundle does not
use. _Alternative_: commit the whole export (dead weight in every clone, and a
licence obligation for an unused font); refer to the export directory outside the
repository (a release would depend on a path in somebody's home directory).

**2. One assembler, and it can describe itself without building.** The
development script is replaced by an assembler that takes a configuration
(debug or release) and a signing mode (ad-hoc or Developer ID). Identity is read
from the code's single declaration rather than repeated in the script; the short
version, the build number, the feed address, the release target, and the key are
read from a checked-in release configuration. The assembler also prints the
identity and version it would write, and a test compares that output with the
code's declarations, so drift fails the test suite instead of the release.
_Alternatives_: an Xcode project (the package builds two executables and needs no
Xcode, and a project file would duplicate the version); a Makefile (no better than
a script, and less able to refuse a half-formed bundle); version constants in
Swift (the shell cannot read them safely, and they change every release).

**3. The menu bar mark is a bundle resource, not a package resource.** Both build
shapes copy the PNG pair into the bundle's resources, and the app looks the image
up in the main bundle by name, setting it as a template image. A missing image
degrades to the title alone rather than an empty status item. _Alternatives_: a
SwiftPM resource bundle (`Bundle.module`), which only SwiftPM builds produce, so
the release layout would need a second lookup path; drawing the mark in code
(re-implements a brand asset, and the export exists precisely so nothing does).

**4. The mark joins the title instead of replacing it.** The status item keeps
naming the state, because that is what the switcher is for, and gains the mark
beside it. Whether the platform renders an image and a title together in a
`MenuBarExtra` label is not documented, so the first task after wiring it is an
empirical check against the running app; if the platform renders only one of the
two, the fallback is an AppKit status item that sets the image and the title
directly, with the same presentation feeding it. _Alternative_: an image-only
status item (loses the state the spec requires, and the mark alone says nothing
about what is on).

_Checked before anything was built on it_: a label holding the image and the text
produces a status button whose title is the state and whose image is the mark with
its template flag set, so both render natively and no fallback is needed. A bundle
whose mark is missing renders the title alone, which is the documented fallback.

**5. Sparkle sits behind an app-support protocol.** The presentation gains an
item and the model forwards a choice; the only code that imports the framework is
one adapter in the app target that implements an `UpdateChecking` protocol
declared beside the other presentations. The item is offered only when the bundle
declares a feed, which is what keeps a development build from installing a release
over itself. _Alternatives_: importing the framework in the entry point (logic in
a scene, which the isolation tests forbid); a separate target for the adapter (a
target whose only content is an import and a call).

**6. The daemon derives its requirement from its own signature.** At start-up the
daemon asks for its own code's team identifier: if there is one, it requires the
app's identifier anchored to Apple's chain with that team; if there is none, it
requires the identifier alone. The rule therefore cannot disagree with how the
running binary was actually signed, and a distribution build cannot accept an
ad-hoc client. A test asserts both requirement strings, and the release refuses to
sign with an identity whose team differs from the one the configuration names.
_Alternatives_: a build flag selecting the requirement (a flag that can be set
wrongly silently weakens the boundary); a hard-coded team constant (needs the same
guard against the signing identity, and cannot describe a development build); the
existing `shipping` helper chosen by hand (same problem, and the choice would live
in the daemon's entry point rather than in its signature).

**7. The daemon stops when it has nothing to serve.** The daemon counts open
connections and exits after a documented idle period, which is what makes "the
installed build answers the next request" true after an update. The client's
repeat covers only a connection that died before there was an answer, never a
request that was given its whole bound, so the documented bound on a write still
holds and a helper that says nothing is reported rather than asked twice. A
helper that is not running is a state the app already names and offers to
repair, so the two rules do not overlap. The client
attempts a request once more when the connection dies before a reply, so the
window between the timer firing and the process exiting is not a failure a user
sees. _Alternatives_: leave the daemon resident (a release that fixes the daemon
takes effect at the next logout, and the privileged rule in force is the one from
whenever the process started); have the app kill the daemon after an update (the
app cannot signal a root-owned process, and asking the privileged side to
terminate itself is a larger interface).

**8. Release tooling comes from a pinned Sparkle distribution.** The EdDSA key is
generated once by the vendor's tool into the login keychain; the public key is
committed in the release configuration and stamped into the property list; the
private key never enters the repository. Signing archives and generating the feed
are done by the vendor's tools from a distribution whose version and checksum are
pinned and verified before use. _Alternatives_: sign with CryptoKit and generate
the feed ourselves (smaller, but it means reconstructing a security format from
documentation and testing it against a single client); fetch the tools unpinned
from the latest release (a security-critical binary that changes without review).

**9. The framework keeps its XPC services.** Sandboxing is not used and the
services are optional, but removing them means re-sealing the framework after a
deletion and diverging from what the vendor ships and tests. They are re-signed
with the rest of the nested code, following the vendor's documented order and
preserving the downloader service's entitlements. _Alternative_: remove them to
save a few hundred kilobytes (a follow-up once the update path is proven on a real
upgrade).

**10. Third-party licence text is committed, not extracted.** The framework's
licence text is stored in the repository beside the assets and copied into the
bundle, so the release does not depend on what a downloaded archive happens to
contain, and a task updates it when the pinned version changes. _Alternative_:
copy the licence from the resolved artefact at build time (silently ships nothing
when the artefact omits it).

**11. Publishing to GitHub is its own script and its own step.** Building,
signing, and notarizing have no network dependency beyond Apple's service; the
publish step creates the release and uploads the disk image to it, then writes the
feed entry and pushes it. Archives are release assets, addressed by tag and file
name, so an archive's address is stable and a tag is never reused; the feed is a
file GitHub Pages serves with its own ten-minute lifetime, which is inside the
hour the feed's requirement allows. The repository is public, because an
unauthenticated client can reach nothing in a private one, and the feed address
contains the repository's name, which is why the address is chosen once and
recorded in the configuration. The publish step refuses a build number that is not
greater than the one already published, and refuses to write a feed entry whose
archive is not readable at its address. _Alternatives_: Cloudflare R2 behind a
custom domain (independent of repository visibility and free to set a 60-second
lifetime, at the cost of a bucket, a token, and DNS to keep alive); a feed served
as a release asset (GitHub caches those hard, and replacing one means deleting it
first, which is a poor fit for the one file whose whole job is to be fresh); the
raw file host (a five-minute lifetime, but it is not meant to serve a product).

**12. The isolation guard is rescoped rather than deleted.** The guard that
forbids packaging, signing, and update vocabulary in the sources was a statement
that those things did not exist. It becomes a statement about where they live:
none of that vocabulary in the core, protocol, privileged, or app-support
targets, and the update framework's name only in the adapter that implements the
update protocol. _Alternative_: delete the guard (the property it protected —
that privileged and core code cannot reach the update channel — is the one worth
keeping).

## Risks / Trade-offs

- **The EdDSA private key exists only in one keychain** → losing it means
  rotating the key, which Sparkle only permits while the code-signing certificate
  stays the same. The key is backed up out of band before the first release, and
  rotation is documented as a deliberate release, not a repair.
- **Notary credentials are absent on this machine** → the first release stops
  with the missing credential named; `notarytool store-credentials` is part of the
  documented first-release procedure, and the scripts never prompt.
- **Re-signing the embedded framework's helpers can break it** → Sparkle ships its
  own signing recipe, including preserving the downloader service's entitlements;
  the release follows it, verifies strictly afterwards, and the acceptance test is
  a real upgrade rather than a signature check alone.
- **A team-anchored requirement invalidates helper registrations made from an
  ad-hoc build** → development bundles keep the identifier-only rule, so nothing
  developers run changes; a distribution build is installed once and registered
  once.
- **Hardened runtime plus library validation refuses an ad-hoc-signed framework**
  → only the release is signed with the hardened runtime; the development bundle
  stays ad-hoc and without it, which is also what lets it run from a build
  directory.
- **An image and a title in one status item may not render as the platform's
  documentation implies** → the check runs before anything else is built on top of
  it, and the AppKit fallback is scoped and cheap.
- **An idle exit introduces a race with an arriving request** → the timer only
  runs with no open connection, the client retries once, and launchd starts the
  daemon on demand, so the worst case is one extra start-up.
- **The feed's address is effectively permanent, and it names the repository** →
  it is declared in one configuration that both the bundle and the publish step
  read; renaming the repository would strand every installed copy, so a rename is
  a migration rather than an edit.
- **A public repository cannot be made private again without consequence** → the
  history was checked before it was made public: no credentials, no key files, no
  absolute paths, and the test fixtures hold only synthetic names. The source is
  MIT and the README already described the project as open source.
- **The feed host is not under our control** → Pages serves the feed with a fixed
  ten-minute lifetime and GitHub's availability is what an update check depends
  on; that is inside the feed's requirement, and a release that had to be seen
  sooner would be a reason to move the feed, not to change the app.
- **The helper's registration names the bundle it was made from** → an app that
  moves has to be registered again from where it now lives, so the acceptance run
  installs to the applications folder and registers from there.

## Migration Plan

- The assembler replaces the development script in place; no installed copy
  depends on the old shape, and the store and the live file are untouched by
  anything here.
- 1.0 is the first published release, so no existing installation has to migrate
  to a feed that did not exist. A bad release is corrected by publishing a higher
  build number, never by rewriting a published archive or an existing feed entry.
- Rollback of the release tooling is reverting to the ad-hoc assembler: signing
  and publishing are separate scripts, so reverting them cannot affect the store,
  the live file, or the daemon's interface.
- The daemon's idle exit is a lifecycle change, not an interface change: the
  protocol, the block format, and the file it writes are identical.

## Open Questions

- DMG window styling — a background image, an icon layout, and a volume icon — is
  deferred; a plain image with the app and the applications link is enough to
  install from, and styling changes nothing that is tested.
- Delta updates are deferred until the download size justifies them; the feed
  format already admits them, and they need older archives kept alongside the
  feed.
- CI wiring is deferred; the scripts are non-interactive and credential-driven, so
  a runner adds secrets and a trigger rather than changing the release path.
