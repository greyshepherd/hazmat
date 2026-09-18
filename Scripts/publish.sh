#!/bin/bash
#
# Publishes a built release: the disk image becomes an asset of a new release, and
# the feed entry naming it is committed and pushed afterwards. The order is the
# point — an entry is never readable before the archive it names.
#
# The repository, the tag prefix, the feed's path and the branch it is served from
# all come from the release configuration, so this step and the bundle the app
# runs cannot name different feeds.
#
# Usage: Scripts/publish.sh --artifact <path> [options]
#
#   --artifact <path>   the disk image Scripts/release.sh built
#   --config <path>     the release configuration
#   --token-env <name>  the environment variable holding the GitHub token
#                       (default: HAZMAT_GITHUB_TOKEN, then GITHUB_TOKEN)
#   --notes <path>      the release notes (default: release/notes/<version>.md)
#   --published <path>  read the already-published feed from a file rather than
#                       from the repository, for a rehearsal
#   --dry-run           report what would be published, then stop
#
# The token is read from the environment and never prompted for. A run without one
# stops before it uploads anything.
#
# The feed is committed on the branch Pages serves and pushed to origin. The run
# refuses when the working tree is not on that branch, or when it holds anything
# but the feed, so a publish can never carry unrelated work with it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/release/config.json"
ARTIFACT=""
TOKEN_ENV=""
NOTES=""
PUBLISHED_FROM=""
DRY_RUN="false"

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo
    echo "== $*"
}

usage() {
    sed -n '3,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --artifact|--config|--token-env|--notes|--published)
            [ $# -ge 2 ] || fail "$1 needs a value"
            case "$1" in
                --artifact) ARTIFACT="$2" ;;
                --config) CONFIG="$2" ;;
                --token-env) TOKEN_ENV="$2" ;;
                --notes) NOTES="$2" ;;
                --published) PUBLISHED_FROM="$2" ;;
            esac
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
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

[ -f "$CONFIG" ] || fail "no release configuration at $CONFIG"

config_value() {
    plutil -extract "$1" raw -o - "$CONFIG" 2>/dev/null || true
}

SHORT_VERSION="$(config_value shortVersion)"
BUILD_NUMBER="$(config_value buildNumber)"
FEED_URL="$(config_value update.feedURL)"
RELEASE_REPO="$(config_value update.releaseRepo)"
TAG_PREFIX="$(config_value update.tagPrefix)"
FEED_PATH="$(config_value update.feedPath)"
FEED_BRANCH="$(config_value update.feedBranch)"

[ -n "$SHORT_VERSION" ] || fail "$CONFIG names no short version"
printf '%s' "$BUILD_NUMBER" | grep -Eq '^[0-9]+$' || fail "$CONFIG names no integer build number"
[ -n "$FEED_URL" ] || fail "$CONFIG names no feed address"
[ -n "$RELEASE_REPO" ] || fail "$CONFIG names no repository to publish to"
[ -n "$FEED_PATH" ] || fail "$CONFIG names no feed path"
[ -n "$FEED_BRANCH" ] || fail "$CONFIG names no branch the feed is served from"

TAG="$TAG_PREFIX$SHORT_VERSION"
ARCHIVE_NAME="$(basename "${ARTIFACT:-Hazmat-$SHORT_VERSION.dmg}")"
ARCHIVE_URL="https://github.com/$RELEASE_REPO/releases/download/$TAG/$ARCHIVE_NAME"
FEED_FILE="$ROOT/$FEED_PATH"

# MARK: - The token

if [ -z "$TOKEN_ENV" ]; then
    if [ -n "${HAZMAT_GITHUB_TOKEN:-}" ]; then
        TOKEN_ENV="HAZMAT_GITHUB_TOKEN"
    elif [ -n "${GITHUB_TOKEN:-}" ]; then
        TOKEN_ENV="GITHUB_TOKEN"
    fi
fi

TOKEN=""
if [ -n "$TOKEN_ENV" ]; then
    TOKEN="${!TOKEN_ENV:-}"
    [ -n "$TOKEN" ] || fail "$TOKEN_ENV is set but empty"
fi

# MARK: - The artifact

[ -n "$ARTIFACT" ] || ARTIFACT="$ROOT/build/release/Hazmat-$SHORT_VERSION.dmg"
[ -f "$ARTIFACT" ] || fail "no artifact at $ARTIFACT; build one with Scripts/release.sh"
[ -f "$FEED_FILE" ] || fail "no feed at $FEED_FILE"

if [ -z "$NOTES" ]; then
    NOTES="$ROOT/release/notes/$SHORT_VERSION.md"
fi
NOTES_ARGUMENT=()
if [ -f "$NOTES" ]; then
    NOTES_ARGUMENT=(--notes-file "$NOTES")
fi

# MARK: - What the feed already says

# Read from the repository rather than from the served copy: Pages caches the
# feed, and the greatest build number published is what this run is compared to.
# The repository is public, so this needs no credential of its own.
published_feed() {
    if [ -n "$PUBLISHED_FROM" ]; then
        cat "$PUBLISHED_FROM"
        return
    fi
    curl --silent --fail --location \
        "https://raw.githubusercontent.com/$RELEASE_REPO/$FEED_BRANCH/$FEED_PATH" 2>/dev/null || true
}

PUBLISHED="$(published_feed)"
PUBLISHED_MAX="$(printf '%s' "$PUBLISHED" \
    | sed -n 's/.*<sparkle:version>\([0-9][0-9]*\)<\/sparkle:version>.*/\1/p' \
    | sort -n | tail -1)"

if [ -n "$PUBLISHED_MAX" ] && [ "$BUILD_NUMBER" -le "$PUBLISHED_MAX" ]; then
    fail "build $BUILD_NUMBER is not greater than $PUBLISHED_MAX, which the feed already carries"
fi

if [ "$DRY_RUN" = "true" ]; then
    cat <<REPORT
tag:        $TAG
artifact:   $ARTIFACT
archive:    $ARCHIVE_URL
feed:       $FEED_URL
feed file:  $FEED_FILE on $FEED_BRANCH
published:  ${PUBLISHED_MAX:-nothing}
notes:      ${NOTES_ARGUMENT[*]:-generated from the commits}
token:      ${TOKEN_ENV:-none set}
REPORT
    exit 0
fi

[ -n "$TOKEN" ] || fail "no GitHub token: set HAZMAT_GITHUB_TOKEN (or GITHUB_TOKEN) to a token that can create releases in $RELEASE_REPO"
export GH_TOKEN="$TOKEN"

# MARK: - The feed's branch

CURRENT_BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
[ "$CURRENT_BRANCH" = "$FEED_BRANCH" ] \
    || fail "the feed is served from $FEED_BRANCH, but this is $CURRENT_BRANCH; publish from that branch"

FEED_RELATIVE="${FEED_FILE#"$ROOT"/}"
DIRTY="$(git -C "$ROOT" status --porcelain | grep -v " $FEED_RELATIVE$" || true)"
[ -z "$DIRTY" ] \
    || fail "the working tree holds changes that are not the feed:
$DIRTY"

# MARK: - The release

step "publishing $TAG to $RELEASE_REPO"
if gh release view "$TAG" --repo "$RELEASE_REPO" > /dev/null 2>&1; then
    fail "release $TAG already exists; a tag is never reused"
fi

gh release create "$TAG" "$ARTIFACT" \
    --repo "$RELEASE_REPO" \
    --title "Hazmat $SHORT_VERSION" \
    "${NOTES_ARGUMENT[@]}" \
    || fail "the release could not be created"

# MARK: - The archive is readable before the feed names it

step "checking the archive at its address"
readable="$(curl --silent --location --head --output /dev/null --write-out '%{http_code}' "$ARCHIVE_URL")"
[ "$readable" = "200" ] || fail "the archive does not answer at $ARCHIVE_URL (HTTP $readable)"

# MARK: - The feed entry

step "writing the feed entry"
NOTES_URL="https://github.com/$RELEASE_REPO/releases/tag/$TAG"
ENTRY="$("$ROOT/Scripts/appcast-entry.sh" \
    --archive "$ARTIFACT" \
    --url "$ARCHIVE_URL" \
    --notes "$NOTES_URL" \
    --config "$CONFIG")"

awk -v item="$ENTRY" '
    !placed && /<item>/ { print item; placed = 1 }
    !placed && /<\/channel>/ { print item; placed = 1 }
    { print }
' "$FEED_FILE" > "$FEED_FILE.published"
mv "$FEED_FILE.published" "$FEED_FILE"

git -C "$ROOT" add "$FEED_RELATIVE"
git -C "$ROOT" commit --quiet -m "Publish Hazmat $SHORT_VERSION" \
    || fail "the feed could not be committed"
git -C "$ROOT" push --quiet origin "HEAD:$FEED_BRANCH" \
    || fail "the feed could not be pushed to $FEED_BRANCH"

# MARK: - What a client sees

step "checking the feed at its address"
# Pages builds and caches, so the served copy lags the push. What is measured here
# is the lifetime it is served with, not the fact that it is already there.
HEADERS="$(curl --silent --location --head "$FEED_URL" || true)"
LIFETIME="$(printf '%s' "$HEADERS" | sed -n 's/^[Cc]ache-[Cc]ontrol: //p' | tr -d '\r' | sed -n '1p')"
if [ -z "$LIFETIME" ]; then
    LIFETIME="$(printf '%s' "$HEADERS" | sed -n 's/^[Ee]xpires: //p' | tr -d '\r' | sed -n '1p')"
fi
AGE="$(printf '%s' "$HEADERS" | sed -n 's/^[Aa]ge: //p' | tr -d '\r' | sed -n '1p')"

served="$(curl --silent --location "$FEED_URL" | grep -c "<sparkle:version>$BUILD_NUMBER</sparkle:version>" || true)"
if [ "$served" -gt 0 ]; then
    echo "   the feed already answers with build $BUILD_NUMBER"
else
    echo "   the feed is still the copy Pages built before this push; it will answer with build $BUILD_NUMBER within the lifetime below"
fi
echo "   served with: ${LIFETIME:-a lifetime the host did not report}${AGE:+ (this copy is ${AGE}s old)}"

echo
echo "release:   https://github.com/$RELEASE_REPO/releases/tag/$TAG"
echo "archive:   $ARCHIVE_URL"
echo "feed:      $FEED_URL"
echo "version:   $SHORT_VERSION ($BUILD_NUMBER)"
