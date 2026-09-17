#!/bin/bash
#
# Assembles the development bundle: SwiftPM builds the executables, this script
# lays out the app around them and ad-hoc signs the result. It is the shape
# `shipping` will replace with real packaging, and the only reason it exists is
# that SMAppService registers a daemon out of a signed bundle.
#
# Usage: Scripts/make-dev-bundle.sh [debug|release]

set -euo pipefail

CONFIGURATION="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUNDLE_ID="com.greyshepherd.hazmat"
DAEMON_LABEL="com.greyshepherd.hazmat.daemon"
APP_NAME="Hazmat"
APP="$ROOT/build/$APP_NAME.app"
VERSION="0.1.0"

cd "$ROOT"
swift build -c "$CONFIGURATION"
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)"

for executable in HazmatApp HazmatDaemon; do
    if [ ! -x "$BIN/$executable" ]; then
        echo "error: swift build produced no $executable" >&2
        exit 1
    fi
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchDaemons"
cp "$BIN/HazmatApp" "$APP/Contents/MacOS/HazmatApp"
cp "$BIN/HazmatDaemon" "$APP/Contents/MacOS/HazmatDaemon"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>HazmatApp</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

cat > "$APP/Contents/Library/LaunchDaemons/$DAEMON_LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$DAEMON_LABEL</string>
    <key>BundleProgram</key>
    <string>Contents/MacOS/HazmatDaemon</string>
    <key>MachServices</key>
    <dict>
        <key>$DAEMON_LABEL</key>
        <true/>
    </dict>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>$BUNDLE_ID</string>
    </array>
</dict>
</plist>
PLIST

# The daemon first, with its own identifier, then the bundle: signing the bundle
# gives the main executable the app's identifier, and that identifier is what the
# daemon's development requirement names.
codesign --force --sign - --identifier "$DAEMON_LABEL" "$APP/Contents/MacOS/HazmatDaemon"
codesign --force --sign - "$APP"

read -r label < <(/usr/libexec/PlistBuddy -c "Print :Label" "$APP/Contents/Library/LaunchDaemons/$DAEMON_LABEL.plist")
read -r program < <(/usr/libexec/PlistBuddy -c "Print :BundleProgram" "$APP/Contents/Library/LaunchDaemons/$DAEMON_LABEL.plist")
read -r service < <(/usr/libexec/PlistBuddy -c "Print :MachServices:$DAEMON_LABEL" "$APP/Contents/Library/LaunchDaemons/$DAEMON_LABEL.plist" || true)

if [ "$label" != "$DAEMON_LABEL" ] || [ "$program" != "Contents/MacOS/HazmatDaemon" ] || [ "$service" != "true" ]; then
    echo "error: the daemon property list does not name Label, BundleProgram and the mach service" >&2
    exit 1
fi

codesign --verify --strict "$APP/Contents/MacOS/HazmatApp"
codesign --verify --strict "$APP/Contents/MacOS/HazmatDaemon"
codesign --verify --strict "$APP"

echo "bundle:   $APP"
echo "label:    $label"
echo "program:  $program"
echo "service:  $DAEMON_LABEL"
codesign -dv "$APP" 2>&1 | sed -n 's/^/app:      /p'
codesign -dv "$APP/Contents/MacOS/HazmatDaemon" 2>&1 | sed -n 's/^/daemon:   /p'
