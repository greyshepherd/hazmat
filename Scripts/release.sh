#!/bin/bash
#
# Builds the artifact a release publishes: a bundle signed inside out under the
# hardened runtime, notarized and stapled, then a disk image holding it beside a
# link to the applications folder, notarized and stapled in its turn.
#
# Nothing here publishes anything. Every step is a gate: the run stops at the
# first one that fails, and reports what failed rather than leaving a half-built
# artifact behind.
#
# Usage: Scripts/release.sh [options]
#
#   --config <path>          the release configuration
#   --identity <name>        the Developer ID identity to sign with
#   --output <path>          where the disk image is written
#   --keep-working           leave the staging directory behind for inspection
#
# The notarization credential comes from the environment and is never prompted
# for. Set one of:
#
#   HAZMAT_NOTARY_PROFILE                       a notarytool keychain profile
#   HAZMAT_NOTARY_KEY, HAZMAT_NOTARY_KEY_ID    an App Store Connect API key, plus
#     (and HAZMAT_NOTARY_ISSUER for a team key)   the issuer a team key carries
#   HAZMAT_APPLE_ID, HAZMAT_APPLE_TEAM_ID, HAZMAT_APPLE_PASSWORD
#                                               an Apple ID and an app password
#
# The signing identity and the team the configuration names must agree; the
# daemon derives the team it requires from its own signature, so a bundle signed
# by another team would refuse its own client.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/release/config.json"
IDENTITY="${HAZMAT_SIGN_IDENTITY:-}"
OUTPUT=""
KEEP_WORKING="false"

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo
    echo "== $*"
}

usage() {
    sed -n '3,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --config|--identity|--output)
            [ $# -ge 2 ] || fail "$1 needs a value"
            case "$1" in
                --config) CONFIG="$2" ;;
                --identity) IDENTITY="$2" ;;
                --output) OUTPUT="$2" ;;
            esac
            shift 2
            ;;
        --keep-working)
            KEEP_WORKING="true"
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
TEAM_IDENTIFIER="$(config_value teamIdentifier)"
APP_NAME="Hazmat"

[ -n "$SHORT_VERSION" ] || fail "$CONFIG names no short version"
[ -n "$TEAM_IDENTIFIER" ] || fail "$CONFIG names no team identifier"

WORK="$ROOT/build/release/$SHORT_VERSION"
DMG="${OUTPUT:-$ROOT/build/release/$APP_NAME-$SHORT_VERSION.dmg}"
APP="$WORK/$APP_NAME.app"
ZIP="$WORK/$APP_NAME-$SHORT_VERSION.zip"

# MARK: - The notarization credential

NOTARY_ARGS=()
notary_credential() {
    if [ -n "${HAZMAT_NOTARY_PROFILE:-}" ]; then
        NOTARY_ARGS=(--keychain-profile "$HAZMAT_NOTARY_PROFILE")
        return
    fi
    if [ -n "${HAZMAT_NOTARY_KEY:-}" ] || [ -n "${HAZMAT_NOTARY_KEY_ID:-}" ] || [ -n "${HAZMAT_NOTARY_ISSUER:-}" ]; then
        [ -n "${HAZMAT_NOTARY_KEY:-}" ] || fail "an App Store Connect credential needs HAZMAT_NOTARY_KEY, the path to the API key"
        [ -n "${HAZMAT_NOTARY_KEY_ID:-}" ] || fail "HAZMAT_NOTARY_KEY is set without HAZMAT_NOTARY_KEY_ID"
        NOTARY_ARGS=(--key "$HAZMAT_NOTARY_KEY" --key-id "$HAZMAT_NOTARY_KEY_ID")
        # A team key needs its issuer and an individual key must not carry one, so
        # the issuer is passed only when it is set.
        [ -n "${HAZMAT_NOTARY_ISSUER:-}" ] && NOTARY_ARGS+=(--issuer "$HAZMAT_NOTARY_ISSUER")
        return
    fi
    if [ -n "${HAZMAT_APPLE_ID:-}" ] || [ -n "${HAZMAT_APPLE_TEAM_ID:-}" ] || [ -n "${HAZMAT_APPLE_PASSWORD:-}" ]; then
        [ -n "${HAZMAT_APPLE_ID:-}" ] || fail "HAZMAT_APPLE_PASSWORD is set without HAZMAT_APPLE_ID"
        [ -n "${HAZMAT_APPLE_TEAM_ID:-}" ] || fail "HAZMAT_APPLE_ID is set without HAZMAT_APPLE_TEAM_ID"
        [ -n "${HAZMAT_APPLE_PASSWORD:-}" ] || fail "HAZMAT_APPLE_ID is set without HAZMAT_APPLE_PASSWORD"
        NOTARY_ARGS=(--apple-id "$HAZMAT_APPLE_ID" --team-id "$HAZMAT_APPLE_TEAM_ID" --password "$HAZMAT_APPLE_PASSWORD")
        return
    fi
    fail "no notarization credential: set HAZMAT_NOTARY_PROFILE to a 'notarytool store-credentials' profile, or HAZMAT_NOTARY_KEY and HAZMAT_NOTARY_KEY_ID (and HAZMAT_NOTARY_ISSUER for a team key), or HAZMAT_APPLE_ID, HAZMAT_APPLE_TEAM_ID and HAZMAT_APPLE_PASSWORD"
}

# MARK: - Notarize and staple

# The service's answer carries the submission's identifier and status; a
# rejection names neither the offending file nor why, so the log is read for it.
notarize() {
    local artifact="$1" what="$2" submission id status reason
    if ! submission="$(xcrun notarytool submit "$artifact" "${NOTARY_ARGS[@]}" --wait --output-format json)"; then
        fail "$what could not be submitted: $submission"
    fi
    id="$(printf '%s' "$submission" | plutil -extract id raw -o - - 2>/dev/null || true)"
    status="$(printf '%s' "$submission" | plutil -extract status raw -o - - 2>/dev/null || true)"
    if [ "$status" != "Accepted" ]; then
        reason="$(xcrun notarytool log "${id:-}" "${NOTARY_ARGS[@]}" --output-format json 2>/dev/null \
            | plutil -extract issues.0.message raw -o - - 2>/dev/null || true)"
        fail "$what was not accepted: submission ${id:-unknown} is $status${reason:+ — $reason}"
    fi
    echo "   submission $id accepted"
}

staple_and_check() {
    local artifact="$1" what="$2"
    xcrun stapler staple "$artifact" || fail "$what could not be stapled"
    xcrun stapler validate "$artifact" || fail "$what carries no valid ticket"
}

# MARK: - The disk image

# The image carries the identity the bundle was signed with, read from the bundle
# rather than resolved again, so the two cannot disagree about who signed them.
sign_the_image() {
    local image="$1" authority
    authority="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | sed -n '1p')"
    [ -n "$authority" ] \
        || fail "the bundle carries no signing authority, so the image cannot be signed to match it"
    codesign --force --sign "$authority" --timestamp "$image" \
        || fail "the disk image could not be signed"
}

# MARK: - Checks that need no network

# An application is assessed as an executable and a disk image as the primary
# signature of the thing a person opens; passing the wrong context to either
# reports a rejection that says nothing about the artifact.
assess_application() {
    local result
    result="$(spctl --assess --type exec --verbose=4 "$APP" 2>&1)" \
        || fail "the application was refused by the system's assessment: $result"
    echo "   the application is accepted for distribution"
}

assess_image() {
    local image="$1" result
    result="$(spctl --assess --type open --context context:primary-signature --verbose=4 "$image" 2>&1)" \
        || fail "the disk image was refused by the system's assessment: $result"
    echo "   the disk image is accepted for distribution"
}

# MARK: - The run

notary_credential

step "assembling and signing the release bundle"
"$ROOT/Scripts/assemble-bundle.sh" release \
    --config "$CONFIG" \
    --identity "$IDENTITY" \
    --output "$APP" \
    || fail "the bundle could not be assembled"

# The assembler verified the bundle's own report against the configuration, so a
# wrong version has already stopped the run by the time this is reached.

step "notarizing the application"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP" "the application"
staple_and_check "$APP" "the application"
rm -f "$ZIP"

step "building the disk image"
rm -f "$DMG"
mkdir -p "$(dirname "$DMG")"
STAGE="$WORK/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null \
    || fail "the disk image could not be built"
rm -rf "$STAGE"

# Signed before it is notarized: the ticket covers the image as it is submitted,
# and an unsigned image is one the system's assessment cannot evaluate at all.
sign_the_image "$DMG"

step "notarizing the disk image"
notarize "$DMG" "the disk image"
staple_and_check "$DMG" "the disk image"

step "verifying the artifacts"
"$ROOT/Scripts/verify-bundle.sh" "$APP" --config "$CONFIG" || fail "the bundle no longer verifies"
assess_application
assess_image "$DMG"

if [ "$KEEP_WORKING" != "true" ]; then
    rm -rf "$WORK"
fi

echo
echo "artifact:  $DMG"
echo "version:   $SHORT_VERSION ($BUILD_NUMBER)"
echo "team:      $TEAM_IDENTIFIER"
echo
echo "Scripts/publish.sh --artifact '$DMG' publishes it and the feed entry naming it."
