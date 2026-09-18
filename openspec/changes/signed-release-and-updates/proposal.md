# Proposal

## Why

Hazmat is complete enough to use and impossible to hand to anyone else. A
development script assembles it with a minimal property list, no icon, and an
ad-hoc signature; there is no notarized artifact, so Gatekeeper stops it on the
Macs it was written for, and no channel to deliver a fix to somebody who has
installed it. The mark the project already owns is not in the bundle at all.
Shipping is the last thing between this and an install a second person can
perform.

## What Changes

- **One assembler, two build shapes.** A development bundle and a release bundle
  share the layout, the identity, and the version source; they differ in
  signature and in whether the bundle declares an update feed.
- **The version comes from one place.** A checked-in release configuration holds
  the short version and the build number, and the property list is stamped from
  it. A release refuses to build without the feed it must declare.
- **The mark ships.** The exported ICNS becomes the app icon, and the exported
  menu bar template is shown beside the status item's existing state title, from
  the bundle's own resources.
- **A signed, notarized, stapled disk image.** Developer ID signing under the
  hardened runtime, nested code signed inside out, notarized, stapled, and
  verified with the system's own assessment before anything is published.
- **The privileged requirement anchors a team.** A daemon that carries a team
  identifier requires that team, not merely the app's identifier, so a
  distribution build cannot accept an ad-hoc client.
- **An update channel.** Sparkle 2, EdDSA-signed archives, an appcast published to
  GitHub Pages with the archives as release assets of the public repository,
  automatic checks, and a manual check the status item's menu offers when the
  bundle has a feed.
- **Publishing is ordered and guarded.** Archives are published before the feed,
  a build number that is not greater than the published one is refused, and
  nothing goes out that has not passed notarization.

## Capabilities

### New Capabilities

- `app-bundle`: how the application bundle is assembled, the identity and
  version it reports, the brand assets it carries, and what a build must refuse.
- `release-signing`: Developer ID signing under the hardened runtime, the
  distributable disk image, notarization and stapling as gates, and the
  verification that runs before a release is published.
- `update-channel`: the update feed, the signature an archive carries, what the
  appcast states about a release, how the app checks for updates, and the order
  in which a release becomes visible.

### Modified Capabilities

- `menu-bar-switcher`: the status item shows the mark beside the state title, and
  the menu offers a manual update check when the bundle declares a feed.
- `privileged-write`: the client requirement anchors the team when the daemon is
  signed with one, instead of the app's identifier alone.

## Impact

- Adds Sparkle as a dependency of the app target only. The core, protocol, and
  privileged targets stay free of it, and this change adds no method to the XPC
  interface, no change to the block format, and none to the store.
- Replaces the development bundle script with an assembler plus release and
  publish scripts, and adds a release configuration, the exported brand assets,
  and the license text of the embedded framework.
- The daemon's verification rule changes, and with it the tests that assert the
  rule.
- The isolation guard that currently forbids packaging, signing, and update code
  in the sources is replaced by one that scopes it: update code lives only beside
  the update adapter, and none of it reaches the core or the privileged side.
