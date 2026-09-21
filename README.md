<div align="center">
  <img src="Assets/icon-512.png" width="128" alt="The Hazmat icon: a gas mask on a dark tile">
  <h1>Hazmat</h1>
  <p><strong>A hosts file manager for Apple Silicon Macs.</strong></p>
  <p>
    <a href="https://github.com/greyshepherd/hazmat/releases/latest">Download</a> ·
    <a href="CHANGELOG.md">Changelog</a> ·
    <a href="LICENSE">MIT License</a>
  </p>
</div>

---

Hazmat keeps named profiles of hosts entries — local development overrides, a
tracker blocklist, a staging environment — and switches between them from the
menu bar. It is inspired from
[Gas Mask](https://github.com/2ndalpha/gasmask), written from scratch for
Apple Silicon.

<p align="center">
  <img src="Assets/screenshot.png" alt="The Hazmat window: profiles and fragments on the left, the work profile's two layers in the middle, and the 46 entries they resolve to on the right" width="85%">
</p>

**Disclaimer**: This codebase was built entirely by pairing with an AI agent — no code was handwritten by a human.

## Installing

```
brew tap greyshepherd/tap
brew trust greyshepherd/tap
brew install --cask hazmat
```
On first apply, Hazmat offers to install its helper — the one step that needs
your password, and the only thing that gives it permission to write
`/etc/hosts`.

## Features

- **Profiles and fragments.** A profile is an ordered list of fragments —
  reusable blocks of entries shared between profiles. Later layers win
  conflicts.
- **Menu bar switcher.** The menu bar shows the current state at a glance and
  switches profiles without opening a window.
- **See it before it lands.** The window shows a profile's layers and the
  exact block they resolve to — as text or a table — before anything is
  written to `/etc/hosts`.
- **Fragments fetched from a URL.** A fragment can record where it comes from —
  a published tracker blocklist, say — and refresh itself on its own interval.
  It is fetched at launch when its interval has elapsed, while Hazmat runs, and
  on demand from its row. The default interval is 24 hours and the shortest is
  15 minutes; zero means only when asked. The text is stored as an ordinary
  fragment, so profiles stack it like any other.
- **Applying is a review step.** A confirmation names the file and the entry
  count, the block it replaces is kept so the change can be reverted.
- **Drift detection.** The active profile is read back from the file's bytes,
  so an edit made outside Hazmat is reported as drift rather than silently
  overwritten.
- **A fetch is bounded before it is stored.** HTTPS only, redirects that leave
  HTTPS refused, conditional on `ETag`/`Last-Modified`, and bounded in time and
  size. A body that is not valid UTF-8, that is larger than the block bound, or
  that carries a `hazmat:` directive is refused whole with its reason, and the
  fragment keeps the text it had. A refresh that changes an applied profile's
  block is applied the way an edit is, and a live file that has moved since is
  reported as drift rather than overwritten.

## How it works

A profile's fragments resolve, in order, into a single block of entries between
`# >>> hazmat:managed v1 >>>` markers. A privileged helper — installed once
from the app, and which only accepts bytes signed by the same team — splices
that block into `/etc/hosts` and leaves every other line of the file untouched.
The app itself needs no privileges: profiles are edited in a plain folder on
disk (its location is choosable in Settings), and that store, not the hosts
file, is the source of truth. The store holds `fragments/`, `profiles/`, and a
`remote/` sidecar per fragment fetched from a URL, so a copied or
version-controlled store keeps its sources. Switching profiles or turning the
block off restores the rest of the file exactly as it was.

Fragments are plain text, and a line is read the same whether it ends in `\n` or
`\r\n`. A block of a few hundred thousand short entries fits inside the helper's
16 MiB write bound. The store is read every time it is asked — a window refresh,
a click on the menu bar — and what was derived from a file is reused only while
the bytes read come back identical, so a fragment another tool changed is read
as it is now rather than as it was.

## Requirements

- A Mac with Apple silicon
- macOS 15 (Sequoia) or later

## Troubleshooting

### An apply is refused because `/etc/hosts` carries an access-control list

The window reports `the privileged side refused: the file carries an
access-control list: /etc/hosts`, and the file is left exactly as it was.

This usually happens because an ACL was applied to `/etc/hosts` by the user
or another tool like Gas Mask.

```sh
ls -le /etc/hosts          # access-control entries print under the file
sudo chmod -N /etc/hosts   # remove them
ls -le /etc/hosts          # verify, then apply again
```

## Documentation

| Document | What it covers |
| --- | --- |
| [CHANGELOG.md](CHANGELOG.md) | What changed in each release |
| [BUILDING.md](BUILDING.md) | Build and test from source |
| [RELEASE.md](RELEASE.md) | Cutting and publishing a release (maintainers) |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Reporting bugs and sending changes |

## License

[MIT](LICENSE) © Grey Shepherd
