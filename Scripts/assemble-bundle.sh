#!/bin/bash
#
# Assembles the application bundle. The development bundle and the release bundle
# are the same bundle around the same executables: they differ in the signature
# they carry and in whether the property list declares an update feed.
#
# Everything the bundle reports comes from one place: the identity from
# HazmatIdentity, the version and the feed from the release configuration.
#
# Usage: Scripts/assemble-bundle.sh [debug|release] [options]
#
#   --configuration <debug|release>  what SwiftPM builds (default: debug)
#   --signing <adhoc|developer-id>   how the bundle is signed (default: adhoc for
#                                    debug, developer-id for release)
#   --identity <name>                the signing identity to use, when the
#                                    keychain holds more than one candidate
#   --config <path>                  the release configuration
#   --output <path>                  where the bundle is written
#   --declare-feed                   declare the update feed (a release does this
#                                    by default; a debug bundle does not)
#   --print-config                   report the identity and version, then stop

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY_SOURCE="$ROOT/Sources/HazmatProtocol/HazmatIdentity.swift"
PACKAGE="$ROOT/Package.swift"
APP_NAME="Hazmat"

CONFIGURATION="debug"
SIGNING=""
IDENTITY="${HAZMAT_SIGN_IDENTITY:-}"
CONFIG="$ROOT/release/config.json"
OUTPUT=""
DECLARE_FEED=""
PRINT_CONFIG="false"

fail() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    sed -n '3,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        debug|release)
            CONFIGURATION="$1"
            shift
            ;;
        --configuration|--signing|--identity|--config|--output)
            [ $# -ge 2 ] || fail "$1 needs a value"
            case "$1" in
                --configuration) CONFIGURATION="$2" ;;
                --signing) SIGNING="$2" ;;
                --identity) IDENTITY="$2" ;;
                --config) CONFIG="$2" ;;
                --output) OUTPUT="$2" ;;
            esac
            shift 2
            ;;
        --declare-feed)
            DECLARE_FEED="true"
            shift
            ;;
        --print-config)
            PRINT_CONFIG="true"
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

case "$CONFIGURATION" in
    debug|release) ;;
    *) fail "configuration must be debug or release, not '$CONFIGURATION'" ;;
esac

if [ -z "$SIGNING" ]; then
    if [ "$CONFIGURATION" = "release" ]; then
        SIGNING="developer-id"
    else
        SIGNING="adhoc"
    fi
fi
case "$SIGNING" in
    adhoc|developer-id) ;;
    *) fail "signing must be adhoc or developer-id, not '$SIGNING'" ;;
esac
if [ "$CONFIGURATION" = "debug" ] && [ "$SIGNING" = "developer-id" ]; then
    SIGNING="adhoc"
fi

[ -f "$CONFIG" ] || fail "no release configuration at $CONFIG"
[ -f "$IDENTITY_SOURCE" ] || fail "no identity declaration at $IDENTITY_SOURCE"
[ -f "$PACKAGE" ] || fail "no package manifest at $PACKAGE"

# MARK: - What the bundle reports

# The identity is declared once, in the code the app, the daemon, and the property
# lists all have to agree with. Reading it here is what makes drift impossible.
read_identity() {
    local key="$1" value
    value="$(sed -n "s/.*static let $key = \"\([^\"]*\)\".*/\1/p" "$IDENTITY_SOURCE")"
    value="${value%%$'\n'*}"
    [ -n "$value" ] || fail "HazmatIdentity declares no $key"
    printf '%s' "$value"
}

BUNDLE_ID="$(read_identity bundleIdentifier)"
DAEMON_LABEL="$(read_identity daemonLabel)"
MACH_SERVICE="$(read_identity machServiceName)"
DAEMON_PLIST_NAME="$(read_identity daemonPlistName)"
DAEMON_EXECUTABLE="$(read_identity daemonExecutableName)"
APP_EXECUTABLE="$(read_identity appExecutableName)"

config_value() {
    plutil -extract "$1" raw -o - "$CONFIG" 2>/dev/null || true
}

SHORT_VERSION="$(config_value shortVersion)"
BUILD_NUMBER="$(config_value buildNumber)"
TEAM_IDENTIFIER="$(config_value teamIdentifier)"
FEED_URL="$(config_value update.feedURL)"
PUBLIC_KEY="$(config_value update.publicKey)"
RELEASE_REPO="$(config_value update.releaseRepo)"

# The deployment floor is the one the package targets, not a second copy of it.
PLATFORM_FLOOR="$(sed -n 's/.*\.macOS(\.v\([0-9][0-9]*\)).*/\1/p' "$PACKAGE" | sed -n '1p')"
[ -n "$PLATFORM_FLOOR" ] || fail "the package manifest names no macOS deployment floor"
MINIMUM_SYSTEM_VERSION="$PLATFORM_FLOOR.0"

ICON_SOURCE="$ROOT/Assets/$APP_NAME.icns"
MARK_SOURCES=("$ROOT/Assets/menu-bar-template.png" "$ROOT/Assets/menu-bar-template@2x.png")
ICON_NAME="$(basename "$ICON_SOURCE" .icns)"

APP="${OUTPUT:-$ROOT/build/$APP_NAME.app}"

# Only a release declares a feed by default. A development bundle that declared
# one could offer to install a release over itself.
if [ -z "$DECLARE_FEED" ]; then
    DECLARE_FEED="false"
    [ "$CONFIGURATION" = "release" ] && DECLARE_FEED="true"
fi

validate_reporting() {
    printf '%s' "$SHORT_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
        || fail "shortVersion is not major.minor.patch in $CONFIG: '$SHORT_VERSION'"
    printf '%s' "$BUILD_NUMBER" | grep -Eq '^[0-9]+$' \
        || fail "buildNumber is not an integer in $CONFIG: '$BUILD_NUMBER'"
    if [ "$DECLARE_FEED" = "true" ]; then
        [ -n "$FEED_URL" ] || fail "declaring a feed needs a feed address in $CONFIG"
        case "$FEED_URL" in
            https://*) ;;
            *) fail "the feed address is not HTTPS: '$FEED_URL'" ;;
        esac
        [ -n "$PUBLIC_KEY" ] || fail "declaring a feed needs the update signing key in $CONFIG"
    fi
    if [ "$CONFIGURATION" = "release" ]; then
        [ -n "$TEAM_IDENTIFIER" ] || fail "a release needs a team identifier in $CONFIG"
        [ -n "$RELEASE_REPO" ] || fail "a release needs a repository to publish to in $CONFIG"
    fi
}

print_config() {
    validate_reporting
    cat <<REPORT
bundleIdentifier=$BUNDLE_ID
appExecutable=$APP_EXECUTABLE
daemonExecutable=$DAEMON_EXECUTABLE
daemonLabel=$DAEMON_LABEL
machServiceName=$MACH_SERVICE
daemonPlistName=$DAEMON_PLIST_NAME
minimumSystemVersion=$MINIMUM_SYSTEM_VERSION
iconName=$ICON_NAME
shortVersion=$SHORT_VERSION
buildNumber=$BUILD_NUMBER
feedURL=$FEED_URL
REPORT
}

if [ "$PRINT_CONFIG" = "true" ]; then
    print_config
    exit 0
fi

validate_reporting

# MARK: - Who signs it

if [ "$SIGNING" = "developer-id" ]; then
    if [ -z "$IDENTITY" ]; then
        IDENTITY="$(security find-identity -v -p codesigning \
            | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | sed -n '1p')"
    fi
    [ -n "$IDENTITY" ] || fail "no Developer ID Application identity is available; set HAZMAT_SIGN_IDENTITY"

    IDENTITY_TEAM="$(printf '%s' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"
    [ -n "$IDENTITY_TEAM" ] || fail "the signing identity names no team: '$IDENTITY'"
    [ "$IDENTITY_TEAM" = "$TEAM_IDENTIFIER" ] \
        || fail "the identity belongs to team $IDENTITY_TEAM, but the configuration names $TEAM_IDENTIFIER"

    SIGN_FLAGS=(--force --sign "$IDENTITY" --options runtime --timestamp)
else
    SIGN_FLAGS=(--force --sign -)
fi

# MARK: - What the bundle carries

for required in "$ICON_SOURCE" "${MARK_SOURCES[@]}" "$ROOT/Licenses/Hazmat.txt" "$ROOT/Licenses/Sparkle.txt"; do
    [ -f "$required" ] || fail "the bundle cannot be complete without $required"
done

# MARK: - Build

echo "building $CONFIGURATION"
cd "$ROOT"
swift build -c "$CONFIGURATION"
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)"

for executable in "$APP_EXECUTABLE" "$DAEMON_EXECUTABLE"; do
    [ -x "$BIN/$executable" ] || fail "the build produced no $executable"
done

FRAMEWORK_SOURCE="$(find "$ROOT/.build/artifacts/sparkle" -maxdepth 4 -type d -name 'Sparkle.framework' -print -quit)"
[ -n "$FRAMEWORK_SOURCE" ] || fail "the update framework was not resolved; run 'swift package resolve'"

# MARK: - Assemble

echo "assembling $APP"
rm -rf "$APP"
mkdir -p \
    "$APP/Contents/MacOS" \
    "$APP/Contents/Resources/Licenses" \
    "$APP/Contents/Frameworks" \
    "$APP/Contents/Library/LaunchDaemons"

install -m 755 "$BIN/$APP_EXECUTABLE" "$APP/Contents/MacOS/$APP_EXECUTABLE"
install -m 755 "$BIN/$DAEMON_EXECUTABLE" "$APP/Contents/MacOS/$DAEMON_EXECUTABLE"
install -m 644 "$ICON_SOURCE" "$APP/Contents/Resources/$ICON_NAME.icns"
for mark in "${MARK_SOURCES[@]}"; do
    install -m 644 "$mark" "$APP/Contents/Resources/$(basename "$mark")"
done
install -m 644 "$ROOT/Licenses/Hazmat.txt" "$APP/Contents/Resources/Licenses/Hazmat.txt"
install -m 644 "$ROOT/Licenses/Sparkle.txt" "$APP/Contents/Resources/Licenses/Sparkle.txt"

# ditto keeps the framework's symlinks and permissions; cp would flatten them.
ditto "$FRAMEWORK_SOURCE" "$APP/Contents/Frameworks/Sparkle.framework"

# The framework ships every architecture; the product is Apple silicon only.
thin_to_arm64() {
    local binary="$1" architectures
    architectures="$(lipo -archs "$binary")"
    case "$architectures" in
        *x86_64*)
            lipo -thin arm64 -output "$binary.arm64" "$binary"
            mv "$binary.arm64" "$binary"
            ;;
    esac
}

while IFS= read -r candidate; do
    case "$(file -b "$candidate")" in
        Mach-O*) thin_to_arm64 "$candidate" ;;
    esac
done < <(find "$APP/Contents/Frameworks" -type f -perm -u+x -print)

# The bundle's own frameworks have to be findable from the executable, and a path
# from the machine that built it has no business in a shipped binary.
normalize_load_paths() {
    local binary="$1" rpath
    # The code signature is written after this, so install_name_tool's warning
    # that it invalidates one is expected and not worth repeating.
    if ! otool -l "$binary" | grep -q '@executable_path/../Frameworks'; then
        install_name_tool -add_rpath @executable_path/../Frameworks "$binary" 2>/dev/null
    fi
    while IFS= read -r rpath; do
        case "$rpath" in
            @executable_path/*|@loader_path*|/usr/lib/swift) ;;
            *)
                echo "  dropping rpath $rpath from $(basename "$binary")"
                install_name_tool -delete_rpath "$rpath" "$binary" 2>/dev/null
                ;;
        esac
    done < <(otool -l "$binary" | sed -n 's/^ *path \(.*\) (offset.*/\1/p')
}

normalize_load_paths "$APP/Contents/MacOS/$APP_EXECUTABLE"
normalize_load_paths "$APP/Contents/MacOS/$DAEMON_EXECUTABLE"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_EXECUTABLE</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MINIMUM_SYSTEM_VERSION</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
$([ "$DECLARE_FEED" = "true" ] && cat <<FEED
    <key>SUFeedURL</key>
    <string>$FEED_URL</string>
    <key>SUPublicEDKey</key>
    <string>$PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
FEED
)
</dict>
</plist>
PLIST

cat > "$APP/Contents/Library/LaunchDaemons/$DAEMON_PLIST_NAME" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$DAEMON_LABEL</string>
    <key>BundleProgram</key>
    <string>Contents/MacOS/$DAEMON_EXECUTABLE</string>
    <key>MachServices</key>
    <dict>
        <key>$MACH_SERVICE</key>
        <true/>
    </dict>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>$BUNDLE_ID</string>
    </array>
</dict>
</plist>
PLIST

# MARK: - Sign

sign() {
    local target="$1"
    shift
    codesign "${SIGN_FLAGS[@]}" "$@" "$target"
}

# Inside out: the framework's services and helpers, then the framework, then the
# daemon with its own identifier, then the app. Signing an outer layer first
# would seal the hashes of inner layers that change afterwards.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
FRAMEWORK_CONTENTS="$FRAMEWORK/Versions/B"

while IFS= read -r bundle; do
    sign "$bundle" --preserve-metadata=entitlements
done < <(find "$FRAMEWORK_CONTENTS" -depth \( -name '*.xpc' -o -name '*.app' \) -print)

while IFS= read -r helper; do
    case "$(file -b "$helper")" in
        Mach-O*) sign "$helper" ;;
    esac
done < <(find "$FRAMEWORK_CONTENTS" -maxdepth 1 -type f -perm -u+x -print)

sign "$FRAMEWORK"
sign "$APP/Contents/MacOS/$DAEMON_EXECUTABLE" --identifier "$DAEMON_LABEL"
sign "$APP"

# MARK: - Verify

"$ROOT/Scripts/verify-bundle.sh" "$APP" --config "$CONFIG"

echo
echo "bundle:    $APP"
echo "identity:  $BUNDLE_ID"
echo "version:   $SHORT_VERSION ($BUILD_NUMBER)"
echo "signing:   $SIGNING${IDENTITY:+ ($IDENTITY)}"
if [ "$DECLARE_FEED" = "true" ]; then
    echo "feed:      $FEED_URL"
else
    echo "feed:      none declared, so the app offers no update check"
fi
