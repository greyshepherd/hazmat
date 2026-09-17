# Release configuration

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
- `update.bucket`, `update.assetPrefix` — where the publish step puts the appcast
  and the archives.
