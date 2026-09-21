#!/bin/bash
#
# Verifies an assembled bundle: what it reports, what it carries, what it loads,
# and that every signature in it is valid. The expectations come from the same
# place the assembler takes them from, so a bundle and this check cannot drift.
#
# Usage: Scripts/verify-bundle.sh <bundle> [--config <path>]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/release/config.json"
BUNDLE=""

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
        --config)
            [ $# -ge 2 ] || fail "--config needs a value"
            CONFIG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            [ -z "$BUNDLE" ] || fail "unknown argument '$1'"
            BUNDLE="$1"
            shift
            ;;
    esac
done

[ -n "$BUNDLE" ] || fail "usage: Scripts/verify-bundle.sh <bundle> [--config <path>]"
[ -d "$BUNDLE" ] || fail "no bundle at $BUNDLE"

EXPECTED="$("$ROOT/Scripts/assemble-bundle.sh" --print-config --config "$CONFIG")"

while IFS='=' read -r key value; do
    case "$key" in
        bundleIdentifier) BUNDLE_ID="$value" ;;
        appExecutable) APP_EXECUTABLE="$value" ;;
        daemonExecutable) DAEMON_EXECUTABLE="$value" ;;
        daemonLabel) DAEMON_LABEL="$value" ;;
        machServiceName) MACH_SERVICE="$value" ;;
        daemonPlistName) DAEMON_PLIST_NAME="$value" ;;
        minimumSystemVersion) MINIMUM_SYSTEM_VERSION="$value" ;;
        iconName) ICON_NAME="$value" ;;
        shortVersion) SHORT_VERSION="$value" ;;
        buildNumber) BUILD_NUMBER="$value" ;;
        feedURL) FEED_URL="$value" ;;
    esac
done <<< "$EXPECTED"

TEAM_IDENTIFIER="$(plutil -extract teamIdentifier raw -o - "$CONFIG" 2>/dev/null || true)"
DAEMON_PLIST="$BUNDLE/Contents/Library/LaunchDaemons/$DAEMON_PLIST_NAME"
INFO_PLIST="$BUNDLE/Contents/Info.plist"

read_plist() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

# MARK: - What it carries

for required in \
    "$BUNDLE/Contents/MacOS/$APP_EXECUTABLE" \
    "$BUNDLE/Contents/MacOS/$DAEMON_EXECUTABLE" \
    "$DAEMON_PLIST" \
    "$INFO_PLIST" \
    "$BUNDLE/Contents/Resources/$ICON_NAME.icns" \
    "$BUNDLE/Contents/Resources/menu-bar-template.png" \
    "$BUNDLE/Contents/Resources/menu-bar-template@2x.png" \
    "$BUNDLE/Contents/Resources/Licenses/Hazmat.txt" \
    "$BUNDLE/Contents/Resources/Licenses/Sparkle.txt"; do
    [ -f "$required" ] || fail "the bundle is missing $required"
done

plutil -lint "$INFO_PLIST" > /dev/null || fail "the property list is not valid"
plutil -lint "$DAEMON_PLIST" > /dev/null || fail "the daemon property list is not valid"

# MARK: - What it reports

[ "$(read_plist "$INFO_PLIST" CFBundleIdentifier)" = "$BUNDLE_ID" ] \
    || fail "the bundle reports identifier '$(read_plist "$INFO_PLIST" CFBundleIdentifier)'"
[ "$(read_plist "$INFO_PLIST" CFBundleShortVersionString)" = "$SHORT_VERSION" ] \
    || fail "the bundle reports version '$(read_plist "$INFO_PLIST" CFBundleShortVersionString)'"
[ "$(read_plist "$INFO_PLIST" CFBundleVersion)" = "$BUILD_NUMBER" ] \
    || fail "the bundle reports build '$(read_plist "$INFO_PLIST" CFBundleVersion)'"
[ "$(read_plist "$INFO_PLIST" CFBundleExecutable)" = "$APP_EXECUTABLE" ] \
    || fail "the bundle names executable '$(read_plist "$INFO_PLIST" CFBundleExecutable)'"
[ "$(read_plist "$INFO_PLIST" CFBundleIconFile)" = "$ICON_NAME" ] \
    || fail "the bundle names icon '$(read_plist "$INFO_PLIST" CFBundleIconFile)'"
[ "$(read_plist "$INFO_PLIST" LSMinimumSystemVersion)" = "$MINIMUM_SYSTEM_VERSION" ] \
    || fail "the bundle declares minimum system version '$(read_plist "$INFO_PLIST" LSMinimumSystemVersion)'"
# The application is launched in malloc's space-efficient mode: what it frees
# goes back to the system rather than into malloc's caches, which is what
# keeps an application that lives in the menu bar small once its window closes.
[ "$(read_plist "$INFO_PLIST" "LSEnvironment:MallocSpaceEfficient")" = "1" ] \
    || fail "the bundle does not launch the application in malloc's space-efficient mode"

[ "$(read_plist "$DAEMON_PLIST" Label)" = "$DAEMON_LABEL" ] || fail "the daemon property list names another label"
[ "$(read_plist "$DAEMON_PLIST" BundleProgram)" = "Contents/MacOS/$DAEMON_EXECUTABLE" ] \
    || fail "the daemon property list names another program"
[ "$(read_plist "$DAEMON_PLIST" "MachServices:$MACH_SERVICE")" = "true" ] \
    || fail "the daemon property list does not publish $MACH_SERVICE"

# MARK: - What it loads

verify_self_contained() {
    local binary="$1" dependency relative offenders=()
    while IFS= read -r dependency; do
        case "$dependency" in
            /usr/lib/*|/System/Library/*) continue ;;
            @rpath/*)
                relative="${dependency#@rpath/}"
                [ -e "$BUNDLE/Contents/Frameworks/$relative" ] || offenders+=("$dependency")
                ;;
            @executable_path/*)
                relative="${dependency#@executable_path/}"
                [ -e "$BUNDLE/Contents/MacOS/$relative" ] || offenders+=("$dependency")
                ;;
            *) offenders+=("$dependency") ;;
        esac
    done < <(otool -L "$binary" | sed -n 's/^[[:space:]]*\([^ ]*\) (compatibility.*/\1/p')

    if [ ${#offenders[@]} -gt 0 ]; then
        local list="${offenders[0]}"
        local extra
        for extra in "${offenders[@]:1}"; do list="$list, $extra"; done
        fail "$(basename "$binary") loads $list, which is outside the bundle"
    fi

    while IFS= read -r rpath; do
        case "$rpath" in
            @executable_path/*|@loader_path*|/usr/lib/swift) ;;
            *) fail "$(basename "$binary") carries the rpath $rpath from wherever it was built" ;;
        esac
    done < <(otool -l "$binary" | sed -n 's/^ *path \(.*\) (offset.*/\1/p')
}

verify_self_contained "$BUNDLE/Contents/MacOS/$APP_EXECUTABLE"
verify_self_contained "$BUNDLE/Contents/MacOS/$DAEMON_EXECUTABLE"

# MARK: - What it is signed with

signed_items=(
    "$BUNDLE/Contents/MacOS/$APP_EXECUTABLE"
    "$BUNDLE/Contents/MacOS/$DAEMON_EXECUTABLE"
)
if [ -d "$BUNDLE/Contents/Frameworks/Sparkle.framework" ]; then
    while IFS= read -r item; do
        signed_items+=("$item")
    done < <(find "$BUNDLE/Contents/Frameworks" -depth \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' \) -print)
fi

for item in "${signed_items[@]}"; do
    codesign --verify --strict "$item" 2>/dev/null \
        || fail "$(basename "$item") does not carry a valid signature"
    team="$(codesign -dv "$item" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    [ "$team" = "not set" ] && team=""
    if [ -n "$team" ] && [ -n "$TEAM_IDENTIFIER" ] && [ "$team" != "$TEAM_IDENTIFIER" ]; then
        fail "$(basename "$item") is signed by team $team, not $TEAM_IDENTIFIER"
    fi
done

codesign --verify --strict "$BUNDLE" || fail "the bundle's own signature is not valid"

# MARK: - What it offers

feed="$(read_plist "$INFO_PLIST" SUFeedURL)"
key="$(read_plist "$INFO_PLIST" SUPublicEDKey)"
if [ -n "$key" ] && [ -z "$feed" ]; then
    fail "the bundle carries an update signing key but no feed"
fi
if [ -n "$feed" ]; then
    [ -n "$key" ] || fail "the bundle declares a feed but carries no signing key"
    [ "$feed" = "$FEED_URL" ] || fail "the bundle declares the feed '$feed', not '$FEED_URL'"
fi

echo "verified: $BUNDLE"
echo "  identity:  $BUNDLE_ID $SHORT_VERSION ($BUILD_NUMBER)"
details="$(codesign -dv "$BUNDLE" 2>&1 || true)"
team="$(sed -n 's/^TeamIdentifier=//p' <<< "$details")"
[ "$team" = "not set" ] && team=""
if grep -q 'flags=.*(runtime)' <<< "$details"; then
    runtime="hardened runtime"
else
    runtime="no hardened runtime"
fi
if grep -q '^Timestamp=' <<< "$details"; then
    timestamp="timestamped"
else
    timestamp="no timestamp"
fi
echo "  signing:   $runtime, $timestamp${team:+, team $team}"
echo "  feed:      ${feed:-none declared}"
