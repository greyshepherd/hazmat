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
#   --notes <path>      the release notes, for a release whose notes are not the
#                       changelog's (default: the version's changelog section)
#   --published <path>  read the already-published feed from a file rather than
#                       from the repository, for a rehearsal
#   --dry-run           report what would be published, then stop
#
# The release page carries the changelog: the release body is the section
# CHANGELOG.md holds for the version being published, and a version it does not
# carry stops the run.
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
    # Every comment line above the code, so a line added to the header cannot
    # quietly shorten what --help prints.
    awk 'NR > 2 && !/^#/ { exit } NR > 2 { print }' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# MARK: - The notes the release page carries

# The release page carries the changelog: the release body is the section
# CHANGELOG.md holds for the version being published, so the page and the file
# cannot say different things. A version the changelog does not carry stops the run
# rather than publishing a page with nothing on it, and `--notes` answers for a
# release whose notes are not the changelog's.
CHANGELOG="$ROOT/CHANGELOG.md"
NOTES_FILE=""
PUBLISHED_FEED=""
SERVED_ARCHIVE=""
remove_temporary_files() {
    rm -f "${NOTES_FILE:-}" "${PUBLISHED_FEED:-}" "${SERVED_ARCHIVE:-}"
}
trap remove_temporary_files EXIT

# A section runs from its heading to the next one, and the heading's first word
# must equal the version, so a heading naming a pre-release of it is not the
# section.
notes_section() {
    local version="$1" file="$2"
    awk -v version="$version" '
        /^## / {
            if (in_section) { exit }
            heading = $0
            sub(/^##[ \t]+/, "", heading)
            split(heading, word, /[ \t]+/)
            if (word[1] == version) { in_section = 1; found = 1 }
            next
        }
        in_section { print }
        END { if (!found) exit 1 }
    ' "$file"
}

if [ -n "$NOTES" ]; then
    [ -f "$NOTES" ] || fail "no notes at $NOTES"
    NOTES_ARGUMENT=(--notes-file "$NOTES")
    NOTES_ORIGIN="$NOTES"
else
    NOTES_FILE="$(mktemp)"
    notes_section "$SHORT_VERSION" "$CHANGELOG" > "$NOTES_FILE" \
        || fail "$CHANGELOG carries no $SHORT_VERSION section, so the release page would carry no notes; add one (## $SHORT_VERSION) or pass --notes"
    grep -q '[^[:space:]]' "$NOTES_FILE" \
        || fail "the $SHORT_VERSION section of $CHANGELOG is empty, so the release page would carry no notes"
    NOTES_ARGUMENT=(--notes-file "$NOTES_FILE")
    NOTES_ORIGIN="$CHANGELOG (the $SHORT_VERSION section)"
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
notes:      $NOTES_ORIGIN
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

# MARK: - The tag

# The tag names the commit the release was cut from. This is the only thing that
# knows which commit that is: left to itself, the release host creates the tag at
# whatever its default branch's head happens to be, which need not be the tree the
# artifact was built from, and then the tag names a commit that cannot reproduce
# the release.
step "tagging $TAG"
HEAD_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
SHORT_HEAD="$(git -C "$ROOT" log -1 --format=%h "$HEAD_COMMIT")"

# The remote's tag is authoritative: bringing it first means a tag that already
# names a different commit is seen here rather than pushed over.
if git -C "$ROOT" fetch --quiet --force origin "refs/tags/$TAG:refs/tags/$TAG" 2>/dev/null; then
    TAGGED_COMMIT="$(git -C "$ROOT" rev-parse "refs/tags/$TAG^{commit}")"
    [ "$TAGGED_COMMIT" = "$HEAD_COMMIT" ] \
        || fail "$TAG already names $(git -C "$ROOT" log -1 --format=%h "$TAGGED_COMMIT"), not the commit being published ($SHORT_HEAD); a published tag is never moved, so cut a higher build number"
    echo "   $TAG already names $SHORT_HEAD"
else
    git -C "$ROOT" tag --annotate "$TAG" --message "Hazmat $SHORT_VERSION" \
        || fail "the commit could not be tagged"
    git -C "$ROOT" push --quiet origin "refs/tags/$TAG" \
        || fail "the tag $TAG could not be pushed"
    echo "   $TAG names $SHORT_HEAD"
fi

# MARK: - The release

step "publishing $TAG to $RELEASE_REPO"
local_digest="$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')"
if gh release view "$TAG" --repo "$RELEASE_REPO" > /dev/null 2>&1; then
    # The release is there. A published archive is never replaced, so the only way
    # this is not a refusal is that it already carries these exact bytes — which is
    # what a run that stopped after uploading and before the feed leaves behind.
    # Refusing there would make the feed impossible to write without cutting a
    # version nobody asked for. Which bytes it carries is decided below, where a
    # resumed publish and a fresh one are read the same way.
    echo "   $TAG is published already; the archive it serves is checked next"
else
    # `--verify-tag` is what keeps the tag this step made: without it the host
    # would create its own at the default branch's head.
    gh release create "$TAG" "$ARTIFACT" \
        --repo "$RELEASE_REPO" \
        --title "Hazmat $SHORT_VERSION" \
        --verify-tag \
        "${NOTES_ARGUMENT[@]}" \
        || fail "the release could not be created"
fi

# MARK: - The archive that answers is the one that was built

# The host accepting an upload is not the same as the bytes it serves being the
# bytes built here, so the served copy is hashed rather than only asked for. An
# upload that did not arrive whole is refused before the feed can name it.
step "checking the archive at its address"
SERVED_ARCHIVE="$(mktemp)"
served_status="$(curl --silent --location --output "$SERVED_ARCHIVE" --write-out '%{http_code}' "$ARCHIVE_URL")"
[ "$served_status" = "200" ] || fail "the archive does not answer at $ARCHIVE_URL (HTTP $served_status)"
served_digest="$(shasum -a 256 "$SERVED_ARCHIVE" | awk '{print $1}')"
[ "$served_digest" = "$local_digest" ] \
    || fail "the archive at $ARCHIVE_URL is not the one this run built (published $served_digest, built $local_digest); a published archive is never replaced, so publish a higher build number"
echo "   the archive answers with the bytes built here"

# MARK: - The feed entry

step "writing the feed entry"
NOTES_URL="https://github.com/$RELEASE_REPO/releases/tag/$TAG"
ENTRY="$("$ROOT/Scripts/appcast-entry.sh" \
    --archive "$ARTIFACT" \
    --url "$ARCHIVE_URL" \
    --notes "$NOTES_URL" \
    --config "$CONFIG")"

# The new entry goes above the ones already there, so the feed reads newest first.
# The insertion is built whole and moved into place: a half-written feed is worse
# than a stale one, and the whole file is what a client fetches.
insert_entry() {
    local target
    # `sed =;q` prints the first matching line's number and stops. A grep that
    # matched nothing would fail this assignment under `pipefail`, which is the
    # ordinary case for a feed that holds no items yet.
    target="$(sed -n '/<item/{=;q;}' "$FEED_FILE")"
    if [ -z "$target" ]; then
        target="$(sed -n '/<\/channel>/{=;q;}' "$FEED_FILE")"
    fi
    [ -n "$target" ] || fail "the feed has no channel to put an item in"

    head -n "$((target - 1))" "$FEED_FILE"
    printf '%s\n' "$ENTRY"
    tail -n "+$target" "$FEED_FILE"
}

# The one EXIT trap removes whichever temporary files exist; `mv` has already
# taken this one's name away, so removing it afterwards names nothing.
PUBLISHED_FEED="$(mktemp)"
insert_entry > "$PUBLISHED_FEED"
mv "$PUBLISHED_FEED" "$FEED_FILE"

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
