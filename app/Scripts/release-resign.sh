#!/bin/bash
# Re-signs an archived justscribe.app for distribution outside the App Store.
#
# Sparkle ships its helpers ad-hoc signed and Xcode's embed re-signs only the framework
# itself; notarization rejects every Mach-O without a Developer ID. Sign inside out
# (never --deep: each seal must cover its re-signed children), then the app, whose seal
# covers the framework.
#
# The app is sandboxed, so it must come out with the entitlements it went in with. They
# are read from the archived app, not from justscribe.entitlements: the source file holds
# the unresolved $(PRODUCT_BUNDLE_IDENTIFIER). An app that lost the sandbox would open a
# different data location and drop the user's models and settings, so that is checked.
#
#   release-resign.sh build/justscribe.xcarchive/Products/Applications/justscribe.app \
#       "Developer ID Application: Quassum MB (6WCYZER5LX)"
set -euo pipefail

APP=${1:?usage: release-resign.sh <app> <identity>}
IDENTITY=${2:?usage: release-resign.sh <app> <identity>}
FW="$APP/Contents/Frameworks/Sparkle.framework"
B="$FW/Versions/B"

fail() { echo "error: $*" >&2; exit 1; }

[ -d "$B/XPCServices/Installer.xpc" ] || fail "$APP has no Sparkle installer service"

ENT=$(mktemp)
trap 'rm -f "$ENT"' EXIT
codesign -d --entitlements - --xml "$APP" > "$ENT" 2>/dev/null || fail "$APP is not signed"
[ -s "$ENT" ] || fail "$APP carries no entitlements to preserve"

sign() { codesign -f -s "$IDENTITY" -o runtime --timestamp "$@"; }
sign "$B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$B/XPCServices/Downloader.xpc"
sign "$B/Autoupdate"
sign "$B/Updater.app"
sign "$FW"
sign --entitlements "$ENT" "$APP"

for item in "$B/Autoupdate" "$B/Updater.app" "$B/XPCServices/Installer.xpc" "$B/XPCServices/Downloader.xpc" "$FW" "$APP"; do
    # Captured first: under pipefail, grep -q closing the pipe early fails codesign with SIGPIPE.
    info=$(codesign -dvv "$item" 2>&1) || true
    grep -qF "Authority=$IDENTITY" <<< "$info" || fail "$item is not signed by $IDENTITY"
done

signed=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p -)
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
grep -q '"com.apple.security.app-sandbox" => true' <<< "$signed" || fail "the re-signed app is not sandboxed"
for name in "$bundle_id-spks" "$bundle_id-spki"; do
    grep -qF "\"$name\"" <<< "$signed" || fail "the re-signed app lost the mach-lookup entitlement $name"
done

codesign --verify --deep --strict --verbose=2 "$APP"
echo "re-signed $APP as $IDENTITY; sandbox and Sparkle entitlements intact"
