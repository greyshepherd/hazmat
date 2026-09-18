#!/bin/bash
#
# Generates one appcast item for a release archive: the entry the update channel
# reads to decide whether to offer it. The signature comes from the pinned
# distribution's tool and covers the archive's bytes, so the entry cannot name an
# archive the app would refuse.
#
# The values come from the release configuration and the package manifest, never
# from a second copy of them here.
#
# Usage: Scripts/appcast-entry.sh --archive <path> --url <address> [options]
#
#   --archive <path>   the disk image being released
#   --url <address>    the archive's absolute HTTPS address
#   --notes <address>  the release notes' address (the release page)
#   --config <path>    the release configuration (default: release/config.json)
#   --tools <path>     the pinned tools' directory (default: ask sparkle-tools.sh)
#   --date <date>      the publication time (default: now, in the feed's format)
#   --key-file <path>  a private key file, for a run with no keychain item
#
# The item is printed on stdout.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/Package.swift"
CONFIG="$ROOT/release/config.json"
ARCHIVE=""
ARCHIVE_URL=""
NOTES_URL=""
TOOLS=""
PUB_DATE=""
KEY_FILE=""

fail() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    # Every comment line above the code, so a line added to the header cannot
    # quietly shorten what --help prints.
    awk 'NR > 2 && !/^#/ { exit } NR > 2 { print }' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --archive|--url|--notes|--config|--tools|--date|--key-file)
            [ $# -ge 2 ] || fail "$1 needs a value"
            case "$1" in
                --archive) ARCHIVE="$2" ;;
                --url) ARCHIVE_URL="$2" ;;
                --notes) NOTES_URL="$2" ;;
                --config) CONFIG="$2" ;;
                --tools) TOOLS="$2" ;;
                --date) PUB_DATE="$2" ;;
                --key-file) KEY_FILE="$2" ;;
            esac
            shift 2
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

[ -f "$CONFIG" ] || fail "no release configuration at $CONFIG"
[ -f "$PACKAGE" ] || fail "no package manifest at $PACKAGE"
[ -n "$ARCHIVE" ] || fail "--archive is required"
[ -f "$ARCHIVE" ] || fail "no archive at $ARCHIVE"
[ -n "$ARCHIVE_URL" ] || fail "--url is required"
case "$ARCHIVE_URL" in
    https://*) ;;
    *) fail "the archive's address is not HTTPS: '$ARCHIVE_URL'" ;;
esac

config_value() {
    plutil -extract "$1" raw -o - "$CONFIG" 2>/dev/null || true
}

SHORT_VERSION="$(config_value shortVersion)"
BUILD_NUMBER="$(config_value buildNumber)"
[ -n "$SHORT_VERSION" ] || fail "$CONFIG names no short version"
printf '%s' "$BUILD_NUMBER" | grep -Eq '^[0-9]+$' \
    || fail "$CONFIG names no integer build number: '$BUILD_NUMBER'"

# The floor is the one the package targets, so the feed cannot require an OS the
# build does not.
PLATFORM_FLOOR="$(sed -n 's/.*\.macOS(\.v\([0-9][0-9]*\)).*/\1/p' "$PACKAGE" | sed -n '1p')"
[ -n "$PLATFORM_FLOOR" ] || fail "the package manifest names no macOS deployment floor"
MINIMUM_SYSTEM_VERSION="$PLATFORM_FLOOR.0"

if [ -z "$PUB_DATE" ]; then
    PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
fi

if [ -z "$TOOLS" ]; then
    TOOLS="$("$ROOT/Scripts/sparkle-tools.sh")"
fi
SIGN_UPDATE="$TOOLS/sign_update"
[ -x "$SIGN_UPDATE" ] || fail "no signing tool at $SIGN_UPDATE"

SIGN_ARGUMENTS=(-p)
[ -n "$KEY_FILE" ] && SIGN_ARGUMENTS+=(--ed-key-file "$KEY_FILE")

# The tool reports a missing key on stdout and exits non-zero, so the status is
# what decides whether the output is a signature.
if ! SIGNATURE="$("$SIGN_UPDATE" "${SIGN_ARGUMENTS[@]}" "$ARCHIVE")"; then
    fail "the archive could not be signed: $SIGNATURE"
fi
printf '%s' "$SIGNATURE" | grep -Eq '^[A-Za-z0-9+/]+={0,2}$' \
    || fail "the signing tool returned no signature: $SIGNATURE"

LENGTH="$(stat -f%z "$ARCHIVE")"

# The feed's namespace is declared on the item so the fragment stands on its own
# and can be checked before it is inserted. The elements are the ones the
# framework's own feed generator writes.
cat <<ITEM
    <item xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <title>Hazmat $SHORT_VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$SHORT_VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM_VERSION</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
$([ -n "$NOTES_URL" ] && printf '      <sparkle:releaseNotesLink>%s</sparkle:releaseNotesLink>\n' "$NOTES_URL")
      <enclosure url="$ARCHIVE_URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE" />
    </item>
ITEM
