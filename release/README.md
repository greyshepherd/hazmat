# Releasing

Three things turn a commit into an update somebody installs: the configuration
below, `Scripts/release.sh`, and `Scripts/publish.sh`. The first two run offline
apart from Apple's notarization service; the third is the only step that touches
the network beyond it.

## The configuration

One file names everything a release needs that is not code. The assembler stamps
it into the bundle's property list and the release and publish scripts read it, so
a bundle and the feed it checks cannot disagree.

- `shortVersion` — what a person reads, `CFBundleShortVersionString`.
- `buildNumber` — what the update channel compares, `CFBundleVersion`. It must be
  an integer greater than the greatest already published; the publish step refuses
  otherwise.
- `teamIdentifier` — the team the Developer ID identity must belong to. The daemon
  derives the team it requires from its own signature, so this is only the guard
  that stops a release signing with the wrong certificate.
- `update.feedURL` — the appcast address. A release bundle declares it; a
  development bundle declares nothing, and therefore offers no update check.
- `update.publicKey` — the base64 EdDSA key the app verifies archives against. It
  is empty until the key is generated; a release refuses to assemble without it.
- `update.releaseRepo`, `update.tagPrefix` — the repository a release is published
  to, and the tag prefix its releases are named with. Archives are release assets,
  so they are served from the release, not from the repository.
- `update.feedPath` — where the appcast is written in that repository.
- `update.feedBranch` — the branch Pages serves, which is the branch the feed is
  committed on and pushed to.

## The pinned tools

`release/sparkle.json` names the Sparkle distribution the release tooling uses:
`version` and `url` are the release it fetches, and `sha256` is the digest it
checks the download against. Nothing else fetches a binary.

`Scripts/sparkle-tools.sh` downloads it, verifies it against the checksum, and
refuses anything that does not match before a tool from it runs. It prints the
directory holding the tools, and the other scripts take the path from it rather
than fetching anything themselves. `Scripts/appcast-entry.sh` uses the signing
tool from it to sign one archive and print the feed item for it; the publish step
calls that script rather than duplicating the entry.

The pin and the version `Package.swift` resolves must agree: the framework the
bundle embeds and the tools that sign the archive come from the same release, and
the test suite fails when they drift.

## Cutting a release

```
Scripts/release.sh
```

The run assembles the release bundle from the configuration, signs it inside out
under the hardened runtime, notarizes and staples the app, builds a disk image
holding the app beside a link to the applications folder, notarizes and staples
the image, and assesses both with the system's own tools. It stops at the first
failure and reports it; a wrong version, a missing identity, and a rejected
notarization all stop the run before anything is published.

The notarization credential comes from the environment and is never prompted for.
`notarytool` accepts two kinds, and either works here:

| Credential | Environment |
| --- | --- |
| A `notarytool` keychain profile | `HAZMAT_NOTARY_PROFILE` |
| An App Store Connect API key | `HAZMAT_NOTARY_KEY` (the `.p8` path), `HAZMAT_NOTARY_KEY_ID`, and `HAZMAT_NOTARY_ISSUER` for a team key |
| An Apple ID and an app-specific password | `HAZMAT_APPLE_ID`, `HAZMAT_APPLE_TEAM_ID`, `HAZMAT_APPLE_PASSWORD` |

A keychain profile is either kind, stored once:

```
xcrun notarytool store-credentials hazmat \
  --key ~/.appstoreconnect/private_keys/AuthKey_ABC123.p8 --key-id ABC123 --issuer <uuid>
xcrun notarytool store-credentials hazmat --apple-id you@example.com --team-id BHY3LCR536
```

The API key is the better of the two: it is scoped to notarization, revocable on its
own, and needs no app-specific password. An individual key carries no issuer; a
team key must carry one, and a team key used without its issuer fails as
`401 Unauthenticated` — which reads like a bad key rather than a missing argument.

When `iCloud Keychain` is on, `store-credentials` may write the profile to the
synced keychain, where a later `--keychain-profile` lookup does not authenticate
against it even though the store reported success. Storing the key and passing it
with `HAZMAT_NOTARY_KEY`, `HAZMAT_NOTARY_KEY_ID` and `HAZMAT_NOTARY_ISSUER`
avoids the keychain altogether and is what the release has been run with.

The `.p8` is a private key. It belongs in `~/.appstoreconnect/private_keys`, never
in the repository; the ignore rules refuse it, but the location is the real
protection.

The signing identity is found in the keychain, or named with
`HAZMAT_SIGN_IDENTITY`. A run with no credential names the one that is missing and
stops before it submits anything.

## Publishing

```
Scripts/publish.sh --artifact build/release/Hazmat-<version>.dmg
```

The step reads the published feed first and refuses a build number that is not
greater than the greatest it carries. It tags the commit it is running on with the
release's tag — an annotated tag carrying the version — and pushes that before it
creates the release, so the tag names the tree the artifact was built from rather
than whichever commit the host's default branch happens to point at. A tag that
already names another commit is refused rather than moved. It then creates the
release against that tag, uploads the image, checks that the image answers at its
address, and only then writes the feed entry naming it and pushes the feed. An
entry is never readable before the archive it names.

The release page carries the changelog: the release body is the section
`CHANGELOG.md` holds for the version being published, so the page and the file
cannot say different things. A version the changelog does not carry stops the run
before anything is tagged, and a release whose notes are not the changelog's names
its own file with `--notes <path>`. Set `shortVersion`, `buildNumber` and that
section before the run.

The token comes from the environment: `HAZMAT_GITHUB_TOKEN`, or `GITHUB_TOKEN`. It
needs to be able to create releases in the repository the configuration names and
to push to the branch the feed is served from, which a token with `repo` scope
covers. A run without one stops before it uploads anything. `--dry-run` reports
what would be published without touching the repository.

The feed is committed on the branch the configuration names and pushed to origin.
The run refuses when the working tree is not on that branch, or holds anything but
the feed, so a publish cannot carry unrelated work with it.

## The first release

Once, before the first release:

1. **Generate the signing key.** The private key is an EdDSA key in the login
   keychain — service `https://sparkle-project.org`, account `ed25519` — and
   never enters the repository. The public half lives in `update.publicKey`.

   ```
   "$(Scripts/sparkle-tools.sh)/generate_keys"
   ```

   The tool prints the public key. Put it in `update.publicKey` in
   `release/config.json` and commit that.

2. **Back the key up out of band.** Losing it means rotating it, which the
   framework only permits while the code-signing certificate stays the same, so
   the backup is what keeps a lost laptop from being a migration. Store it where
   the keychain is not the only copy.

3. **Store the notarization credential.** `xcrun notarytool store-credentials`
   writes a keychain profile from either an App Store Connect API key or an Apple
   ID and an app-specific password; name it in `HAZMAT_NOTARY_PROFILE`. Nothing
   prompts, so a missing credential is a stopped release rather than a stalled one.

4. **Enable Pages** for the repository, from the branch and the directory the
   configuration names: `update.feedBranch` and the directory of
   `update.feedPath`. The feed's address is what the bundle declares, and it is
   effectively permanent — renaming the repository would strand every installed
   copy.

5. **Confirm the repository is public.** An installed copy fetches the feed and the
   archive without a credential, so nothing in a private repository is reachable.

Then walk the sequence once against a throwaway version: set `shortVersion` and
`buildNumber`, run `Scripts/release.sh`, then `Scripts/publish.sh --dry-run`, then
the publish itself. That exercises every gate before the version anyone keeps.

## What is secret, and where it lives

Nothing here writes a credential to a file in the repository. This is the whole
inventory, and each entry names what losing it costs.

| Secret | Where it lives | If it is lost |
| --- | --- | --- |
| The EdDSA key that signs archives | The login keychain, service `https://sparkle-project.org`, account `ed25519`. Its public half is committed in `update.publicKey` | A rotation, which the framework only permits while the code-signing certificate stays the same — so the backup is the real protection |
| The Developer ID certificate and its private key | The login keychain, as a codesigning identity. `HAZMAT_SIGN_IDENTITY` names one when the keychain holds several | A new certificate issued to the same team. The privileged side requires the team rather than a particular certificate, so an installed copy can still be updated |
| The App Store Connect API key (`.p8`) | `~/.appstoreconnect/private_keys`, or wherever `HAZMAT_NOTARY_KEY` points. The ignore rules refuse `*.p8` and `AuthKey_*` so one cannot be staged by accident | Download another key from App Store Connect; nothing in the repository changes |
| The notarization credential | A `notarytool` keychain profile, or the environment. It is either the API key above or an Apple ID and an app-specific password | Regenerate an app-specific password, or make another key |
| The GitHub token | The environment only — `HAZMAT_GITHUB_TOKEN` or `GITHUB_TOKEN`. No script writes it anywhere | Issue another token |

Everything else is public and belongs in the repository: the release
configuration, the update public key, the feed, the signing identity's name, and
the archives themselves. The signature in a feed entry is over the archive's
bytes and is verified with the committed public key, so it carries no secret.

Two things are worth stating because they are easy to get wrong. A key file is a
private key: it belongs beside your other credentials, never in a working tree,
even one the ignore rules cover. And the update key and the code-signing identity
are separate — the first proves an archive is the one this project signed, the
second proves who built the app — so losing one is not losing the other.

## Accepting an upgrade

The upgrade that matters is the one a person performs, so it is checked rather
than assumed:

1. Install the published build from the disk image into the applications folder,
   and register the helper from there. The registration names the bundle it was
   registered from, so an app that has moved has to be registered again from where
   it now lives.
2. Confirm the helper's state reads as answering rather than only as approved, and
   apply a profile.
3. Cut the next build, upgrade from the app's own menu, and confirm the app reports
   the new version, the store and the live block are untouched, and an apply
   through the helper still succeeds. The daemon that answers must be the updated
   build, which is what its idle exit is for.

## Versions

A published version is never rewritten. A bad release is corrected by publishing a
higher build number, so the feed only ever gains entries and an installed copy only
ever moves forward. The same holds for the tag: it names the commit a release came
from, and a tag that already names one is never moved to another. A release built
from the wrong tree is corrected the same way a bad one is, by cutting a higher
build number.
