#!/bin/bash
#
# Fetches the pinned Sparkle distribution and checks it against the checksum in
# release/sparkle.json before anything in it runs. The tools it carries sign an
# archive and generate the signing key, so a distribution that does not match its
# pin is refused rather than used.
#
# Usage: Scripts/sparkle-tools.sh [--print-bin] [options]
#
#   --print-bin        report the tools' directory, then stop (the default)
#   --pin <path>       the pin to read (default: release/sparkle.json)
#   --cache <path>     where the distribution is kept (default: build/sparkle-tools)
#   --force            download again even when the archive is already cached
#
# The tools' directory is printed on stdout; everything else goes to stderr, so a
# caller can capture the path.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="$ROOT/release/sparkle.json"
CACHE="$ROOT/build/sparkle-tools"
FORCE="false"

fail() {
    echo "error: $*" >&2
    exit 1
}

note() {
    echo "$*" >&2
}

usage() {
    sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --print-bin)
            shift
            ;;
        --pin|--cache)
            [ $# -ge 2 ] || fail "$1 needs a value"
            case "$1" in
                --pin) PIN="$2" ;;
                --cache) CACHE="$2" ;;
            esac
            shift 2
            ;;
        --force)
            FORCE="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument '$1' (try --help)"
            ;;
    esac
done

[ -f "$PIN" ] || fail "no pinned distribution at $PIN"

pin_value() {
    plutil -extract "$1" raw -o - "$PIN" 2>/dev/null || true
}

VERSION="$(pin_value version)"
URL="$(pin_value url)"
CHECKSUM="$(pin_value sha256)"

[ -n "$VERSION" ] || fail "$PIN names no version"
[ -n "$URL" ] || fail "$PIN names no download address"
[ -n "$CHECKSUM" ] || fail "$PIN names no checksum"
case "$URL" in
    https://*) ;;
    *) fail "the download address is not HTTPS: '$URL'" ;;
esac

DIST="$CACHE/$VERSION"
ARCHIVE="$DIST/Sparkle-$VERSION.tar.xz"

if [ "$FORCE" = "true" ] || [ ! -f "$ARCHIVE" ]; then
    note "fetching Sparkle $VERSION"
    mkdir -p "$DIST"
    curl --fail --location --silent --show-error --output "$ARCHIVE.part" "$URL" \
        || { rm -f "$ARCHIVE.part"; fail "the distribution could not be downloaded from $URL"; }
    mv "$ARCHIVE.part" "$ARCHIVE"
fi

ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [ "$ACTUAL" != "$CHECKSUM" ]; then
    # A distribution that is not what was pinned is deleted, so the next run
    # fetches again rather than failing on the same bytes.
    rm -f "$ARCHIVE"
    fail "the distribution is not the pinned one: expected $CHECKSUM, found $ACTUAL"
fi

TOOLS="$DIST/bin"
if [ ! -x "$TOOLS/sign_update" ] || [ ! -x "$TOOLS/generate_keys" ]; then
    rm -rf "$TOOLS"
    tar -xf "$ARCHIVE" -C "$DIST" ./bin \
        || fail "the pinned distribution holds no tools"
fi

for tool in sign_update generate_keys; do
    [ -x "$TOOLS/$tool" ] || fail "the pinned distribution carries no $tool"
done

printf '%s\n' "$TOOLS"
