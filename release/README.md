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

`release/sparkle.json` pins the Sparkle distribution the release tooling uses, and
its checksum. `Scripts/sparkle-tools.sh` downloads it, verifies it against the
checksum, and refuses anything that does not match before a tool from it runs.
Nothing else fetches a binary.

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
Scripts/publish.sh --artifact build/release/Hazmat-1.0.0.dmg
```

The step reads the published feed first and refuses a build number that is not
greater than the greatest it carries. It creates the release, uploads the image,
checks that the image answers at its address, and only then writes the feed entry
naming it and pushes the feed. An entry is never readable before the archive it
names.

The token comes from the environment: `HAZMAT_GITHUB_TOKEN`, or `GITHUB_TOKEN`. A
run without one stops before it uploads anything. `--dry-run` reports what would
be published without touching the repository.

The feed is committed on the branch the configuration names and pushed to origin.
The run refuses when the working tree is not on that branch, or holds anything but
the feed, so a publish cannot carry unrelated work with it.

## The first release

Once, before the first release:

1. **Generate the signing key.** The private key is an EdDSA key in the login
   keychain and never enters the repository.

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
ever moves forward.
