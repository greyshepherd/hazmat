# Building

Hazmat builds from source with Swift 6 and the macOS 15 SDK on an Apple
Silicon Mac.

## Assemble a bundle

```
Scripts/assemble-bundle.sh debug     # signed ad-hoc, declares no update feed
Scripts/assemble-bundle.sh release   # signed with a Developer ID, declares the feed
open build/Hazmat.app
```

Either command assembles `build/Hazmat.app`. A release bundle signs with a
Developer ID identity in your keychain (or the one named by
`HAZMAT_SIGN_IDENTITY`) and stamps the update configuration from
`release/config.json`; see [RELEASE.md](RELEASE.md).

## Inspect a bundle

```
Scripts/verify-bundle.sh build/Hazmat.app
```

Reports what a bundle carries, what it declares, what it loads, and how it is
signed.

## Tests

```
swift test
```

The suite covers profile composition, the hosts block splice, the privileged
protocol, and the packaging: the packaging tests read `release/config.json`,
`release/sparkle.json`, and the licence files, so run the suite after changing
scripts or assets too.

## Keep a development build away from the real store

`HAZMAT_STORE_ROOT` names the store from the environment and is authoritative
over the location chosen in Settings. Point it at a scratch folder while
developing:

```
HAZMAT_STORE_ROOT=/tmp/hazmat-store open build/Hazmat.app
```
