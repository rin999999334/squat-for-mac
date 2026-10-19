#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

MODE=production
case "${1:-}" in
    '') ;;
    --preview) MODE=preview ;;
    *) printf 'Usage: %s [--preview]\n' "$0" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then exit 2; fi

mkdir -p .build/module-cache .build/stamps
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache"
TARGET="$(uname -m)-apple-macosx13.0"
IDENTITY="${SQUAT_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && { [ -e .build/local-signing-identity ] || [ -L .build/local-signing-identity ]; }; then
    if [ ! -f .build/local-signing-identity ] || [ -L .build/local-signing-identity ]; then
        printf 'Invalid local signing configuration; refusing ad hoc fallback.\n' >&2
        exit 1
    fi
    IDENTITY=$(cat .build/local-signing-identity)
    if [ -z "$IDENTITY" ] || [ "$IDENTITY" = '-' ]; then
        printf 'Empty or invalid local signing identity; app was not replaced.\n' >&2
        exit 1
    fi
fi
IDENTITY="${IDENTITY:--}"
# A fixed certificate fingerprint avoids selecting a different identity with
# the same display name. Never silently fall back to ad hoc signing.
if [ "$IDENTITY" != '-' ]; then
    if ! [[ "$IDENTITY" =~ ^[[:xdigit:]]{40}$ ]]; then
        printf 'Signing identity must be a 40-character certificate SHA-1.\n' >&2
        exit 2
    fi
    IDENTITY=$(printf '%s' "$IDENTITY" | tr '[:lower:]' '[:upper:]')
    if ! security find-identity -v -p codesigning | /usr/bin/grep -Fq "$IDENTITY"; then
        printf 'Selected signing identity is unavailable; app was not replaced.\n' >&2
        exit 1
    fi
fi

if [ "$MODE" = preview ]; then
    DESTINATION="$PWD/dist/Squat for Mac Preview.app"
else
    DESTINATION="$PWD/dist/Squat for Mac.app"
fi
CACHE="$PWD/.build/stamps/$MODE-$(uname -m).json"
mkdir -p .build/locks
BUILD_LOCK="$PWD/.build/locks/$MODE.lock"
if ! mkdir "$BUILD_LOCK" 2>/dev/null; then
    printf 'Another %s build is active. App was not changed.\n' "$MODE" >&2
    exit 1
fi
BUILD_STAGE=''
VERIFY_STAGE=''
PREVIOUS_MOVED=0
REPLACEMENT_MOVED=0
COMMITTED=0
cleanup() {
    result=$?
    trap - EXIT
    if [ "$COMMITTED" -ne 1 ]; then
        if [ "$REPLACEMENT_MOVED" -eq 1 ]; then rm -rf "$DESTINATION"; fi
        if [ "$PREVIOUS_MOVED" -eq 1 ]; then
            if ! mv "$BUILD_STAGE/previous.app" "$DESTINATION"; then
                printf 'Previous app retained for recovery: %s\n' "$BUILD_STAGE/previous.app" >&2
                rmdir "$BUILD_LOCK"
                exit 1
            fi
        fi
    fi
    if [ -n "$BUILD_STAGE" ]; then rm -rf "$BUILD_STAGE"; fi
    if [ -n "$VERIFY_STAGE" ]; then rm -rf "$VERIFY_STAGE"; fi
    rmdir "$BUILD_LOCK"
    exit "$result"
}
trap cleanup EXIT
verify_existing_app() {
    if codesign --verify --deep --strict "$DESTINATION" 2>/dev/null; then return 0; fi
    # Finder can reattach FinderInfo on the Desktop. Verify an otherwise exact
    # copy without that metadata, preserving the installed app and its identity.
    VERIFY_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/squat-verify-XXXXXX") || return 1
    if ! /usr/bin/ditto "$DESTINATION" "$VERIFY_STAGE/Squat.app"; then return 1; fi
    xattr -dr com.apple.FinderInfo "$VERIFY_STAGE/Squat.app" 2>/dev/null || true
    codesign --verify --deep --strict "$VERIFY_STAGE/Squat.app" 2>/dev/null
}
TOOLCHAIN="$(xcrun swiftc --version)
$(xcrun --show-sdk-path)
$(xcrun --show-sdk-version)"
FINGERPRINT=$(python3 scripts/build_cache.py inputs --mode "$MODE" \
    --identity "$IDENTITY" --target "$TARGET" --toolchain "$TOOLCHAIN")
if python3 scripts/build_cache.py matches --cache "$CACHE" \
    --fingerprint "$FINGERPRINT" --app "$DESTINATION" \
    && verify_existing_app; then
    printf 'Unchanged; keeping existing app and signature: %s\n' "$DESTINATION"
    exit 0
fi

xcrun swiftc -swift-version 5 -parse-as-library -O \
    -target "$TARGET" -module-cache-path "$PWD/.build/module-cache" \
    Sources/SquatForMac/*.swift -lsqlite3 -o ".build/SquatForMac-$MODE"
BUILD_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/squat-package-XXXXXX")
APP="$BUILD_STAGE/Squat.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/SquatForMac-$MODE" "$APP/Contents/MacOS/SquatForMac"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Sources/SquatForMac/Resources/. "$APP/Contents/Resources/"
if [ "$MODE" = preview ]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.thinkandmove.ui-preview.v27' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Add :SquatPreviewWelcome bool true' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Squat for Mac Preview 0.9.2' "$APP/Contents/Info.plist"
fi
# Remove only Finder metadata from the generated staging bundle.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
codesign --force --sign "$IDENTITY" --options runtime \
    --entitlements SquatForMac.entitlements "$APP"
codesign --verify --deep --strict "$APP"
FINAL_FINGERPRINT=$(python3 scripts/build_cache.py inputs --mode "$MODE" \
    --identity "$IDENTITY" --target "$TARGET" --toolchain "$TOOLCHAIN")
if [ "$FINGERPRINT" != "$FINAL_FINGERPRINT" ]; then
    printf 'Build inputs changed during compilation; existing app was not replaced.\n' >&2
    exit 1
fi
# Keep the last successful app if replacement or final verification fails.
mkdir -p "$(dirname "$DESTINATION")"
if [ -L "$DESTINATION" ]; then printf 'Refusing linked app destination.\n' >&2; exit 1; fi
if [ -e "$DESTINATION" ]; then
    if [ ! -d "$DESTINATION" ]; then exit 1; fi
    mv "$DESTINATION" "$BUILD_STAGE/previous.app"
    PREVIOUS_MOVED=1
fi
mv "$APP" "$DESTINATION"
REPLACEMENT_MOVED=1
verify_existing_app
python3 scripts/build_cache.py record --cache "$CACHE" \
    --fingerprint "$FINGERPRINT" --app "$DESTINATION"
COMMITTED=1
printf 'Built (%s): %s\n' "$MODE" "$DESTINATION"
if [ "$IDENTITY" = '-' ]; then
    printf 'Ad hoc signing: permission may be requested again after code updates. See docs/LOCAL_SIGNING.md\n'
fi
