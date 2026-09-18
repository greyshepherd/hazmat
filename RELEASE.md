# Releasing

Two scripts turn a commit into an update somebody installs:

```
Scripts/release.sh                                            # assemble, sign, notarize, staple, assess
Scripts/publish.sh --artifact build/release/Hazmat-<version>.dmg   # tag, upload, publish the feed
```

`release.sh` assembles the release bundle from `release/config.json`, signs it
inside out under the hardened runtime, notarizes and staples the app and the
disk image, and assesses both with the system's own tools. It stops at the
first failure and reports it. `publish.sh` refuses a build number that is not
greater than the greatest the published feed carries, tags the commit the
release was cut from, uploads the image as a release asset, and only then
writes and pushes the feed entry that installed copies check — an entry is
never readable before the archive it names.

The configuration — versions, signing team, update feed address and public
key, and the repository and branch the feed is published to — lives in
`release/config.json`.

The complete guide is [release/README.md](release/README.md): every field of
the configuration, the credentials each step reads from the environment, the
pinned Sparkle tools, the one-time setup a first release needs, the inventory
of what is secret and where it lives, and the upgrade an installed copy must
be shown to accept.

Versions are never rewritten: a bad release is corrected by publishing a
higher build number, and a tag that already names a commit is refused rather
than moved.
