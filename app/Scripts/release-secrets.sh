#!/bin/bash
# Sets the repository secrets the Release workflow needs, with the GitHub CLI.
# Run it once on the maintainer's Mac; docs/release.md explains each secret.
#
# It asks for what only you have, checks each value before sending it, and
# never prints a secret or leaves one on disk:
#   - the Developer ID certificate as a .p12 (Keychain Access → My Certificates →
#     the "Developer ID Application" certificate → Export) and its password;
#   - the App Store Connect API key (.p8), its Key ID and the Issuer ID;
#   - the Sparkle private key, exported from the login keychain (macOS may ask
#     to allow it) and checked against SUPublicEDKey in Info.plist;
#   - optionally the Cloudflare deploy hook URL for the website.
#
#   app/Scripts/release-secrets.sh                 set whatever is missing
#   app/Scripts/release-secrets.sh --all           set all of them again
#   app/Scripts/release-secrets.sh --repo o/name   another repository than this checkout's
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IDENTITY="Developer ID Application: Quassum MB (6WCYZER5LX)"
TEAM_ID="6WCYZER5LX"
SPARKLE_ACCOUNT="JustScribe"
SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

all=false
repo=""
while [ $# -gt 0 ]; do
    case "$1" in
        --all)  all=true; shift ;;
        --repo) repo=${2-}; shift 2 ;;
        *) echo "usage: release-secrets.sh [--all] [--repo owner/name]" >&2; exit 1 ;;
    esac
done

say()  { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null || fail "the GitHub CLI (gh) is not installed"
gh auth status >/dev/null 2>&1 || fail "gh is not signed in; run: gh auth login"
[ -n "$repo" ] || repo=$(cd "$ROOT" && gh repo view --json nameWithOwner --jq .nameWithOwner)
[ -n "$repo" ] || fail "cannot tell which repository this is; pass --repo owner/name"

WORK=$(mktemp -d)
KEYCHAIN="$WORK/check.keychain-db"
cleanup() {
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

existing=$(gh secret list --repo "$repo" --json name --jq '.[].name')
has() { grep -qx "$1" <<< "$existing"; }
# True when the secret should be set in this run.
wanted() { $all || ! has "$1"; }
# set_secret <name>: the value comes on stdin, so it never appears in a process list.
set_secret() {
    gh secret set "$1" --repo "$repo" >/dev/null
    note "set $1"
}
ask()        { local reply; read -r -p "   $1: " reply; printf '%s' "$reply"; }
ask_hidden() { local reply; read -r -s -p "   $1: " reply; echo >&2; printf '%s' "$reply"; }
# A path as typed or dragged from Finder: quotes and backslash-escaped spaces removed, ~ expanded.
ask_path() {
    local reply
    reply=$(ask "$1")
    reply=${reply#\'}; reply=${reply%\'}; reply=${reply#\"}; reply=${reply%\"}
    reply=${reply//\\ / }
    reply=${reply/#\~/$HOME}
    printf '%s' "${reply%"${reply##*[![:space:]]}"}"
}

echo "Setting the release secrets on $repo."
if $all; then echo "Every secret is asked for again (--all)."; else echo "Secrets that already exist are left alone (use --all to replace them)."; fi

# --- 1. The Developer ID certificate -----------------------------------------
say "Developer ID certificate"
if wanted MACOS_CERTIFICATE_P12 || wanted MACOS_CERTIFICATE_PASSWORD; then
    note "Export \"$IDENTITY\" from Keychain Access as a .p12 first."
    p12=$(ask_path "Path to the .p12")
    [ -f "$p12" ] || fail "no file at $p12"
    password=$(ask_hidden "Its password")
    # The same import the workflow does, into a keychain that is thrown away.
    security create-keychain -p check "$KEYCHAIN"
    security unlock-keychain -p check "$KEYCHAIN"
    if ! security import "$p12" -k "$KEYCHAIN" -P "$password" -T /usr/bin/codesign >/dev/null 2>&1; then
        fail "the .p12 could not be imported with that password"
    fi
    identities=$(security find-identity -v -p codesigning "$KEYCHAIN")
    grep -qF "\"$IDENTITY\"" <<< "$identities" || fail "the .p12 does not hold the identity $IDENTITY (certificate and private key)"
    count=$(grep -c '"' <<< "$identities" || true)
    [ "$count" -eq 1 ] || note "warning: the .p12 holds $count signing identities; export only the Developer ID one if you can"
    security delete-keychain "$KEYCHAIN"
    base64 -i "$p12" | set_secret MACOS_CERTIFICATE_P12
    printf '%s' "$password" | set_secret MACOS_CERTIFICATE_PASSWORD
    unset password
    note "you can delete $p12 now"
else
    note "MACOS_CERTIFICATE_P12 and MACOS_CERTIFICATE_PASSWORD already set"
fi
if wanted MACOS_SIGNING_IDENTITY; then printf '%s' "$IDENTITY" | set_secret MACOS_SIGNING_IDENTITY; else note "MACOS_SIGNING_IDENTITY already set"; fi
if wanted APPLE_TEAM_ID; then printf '%s' "$TEAM_ID" | set_secret APPLE_TEAM_ID; else note "APPLE_TEAM_ID already set"; fi

# --- 2. The App Store Connect API key (notarization) --------------------------
say "App Store Connect API key"
if wanted ASC_API_KEY_P8 || wanted ASC_API_KEY_ID || wanted ASC_API_ISSUER_ID; then
    p8=$(ask_path "Path to AuthKey_XXXXXXXXXX.p8")
    [ -f "$p8" ] || fail "no file at $p8"
    grep -q "BEGIN PRIVATE KEY" "$p8" || fail "$p8 does not look like a .p8 private key"
    guess=$(basename "$p8" .p8); guess=${guess#AuthKey_}
    key_id=$(ask "Key ID [$guess]"); key_id=${key_id:-$guess}
    [[ "$key_id" =~ ^[A-Z0-9]{10,}$ ]] || fail "a Key ID is ten or more capital letters and digits, got: $key_id"
    issuer=$(ask "Issuer ID")
    [[ "$issuer" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]] || fail "an Issuer ID is a UUID, got: $issuer"
    # Ask Apple's notary service something harmless, to prove the three belong together.
    if ! xcrun notarytool history --key "$p8" --key-id "$key_id" --issuer "$issuer" >/dev/null 2>"$WORK/notary.err"; then
        sed 's/^/   /' "$WORK/notary.err" >&2
        fail "Apple's notary service rejected this key, Key ID and Issuer ID"
    fi
    note "Apple's notary service accepts the key"
    set_secret ASC_API_KEY_P8 < "$p8"
    printf '%s' "$key_id" | set_secret ASC_API_KEY_ID
    printf '%s' "$issuer" | set_secret ASC_API_ISSUER_ID
    note "you can delete $p8 now (keep it if neural-sheet's setup still needs it)"
else
    note "ASC_API_KEY_P8, ASC_API_KEY_ID and ASC_API_ISSUER_ID already set"
fi

# --- 3. The Sparkle private key ----------------------------------------------
say "Sparkle update key"
if wanted SPARKLE_PRIVATE_KEY; then
    committed=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/justscribe/Info.plist")
    curl -fsSL --retry 3 -o "$WORK/Sparkle.tar.xz" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
    echo "$SPARKLE_SHA256  $WORK/Sparkle.tar.xz" | shasum -a 256 -c - >/dev/null || fail "the Sparkle tools download does not match its checksum"
    tar -xJf "$WORK/Sparkle.tar.xz" -C "$WORK" bin/generate_keys
    note "exporting the key for account $SPARKLE_ACCOUNT from the login keychain (allow it if macOS asks)"
    "$WORK/bin/generate_keys" --account "$SPARKLE_ACCOUNT" -x "$WORK/sparkle.key" >/dev/null \
        || fail "no Sparkle key for account $SPARKLE_ACCOUNT in the login keychain"
    chmod 600 "$WORK/sparkle.key"
    derived=$(xcrun swift "$ROOT/Scripts/release-sparkle-public-key.swift" "$WORK/sparkle.key")
    if [ "$derived" != "$committed" ]; then
        fail "the keychain's key is for public key $derived, but Info.plist has $committed; installed copies would reject every update"
    fi
    note "the key matches SUPublicEDKey in Info.plist"
    set_secret SPARKLE_PRIVATE_KEY < "$WORK/sparkle.key"
    note "Losing this key from both the keychain and the secret means no installed copy can ever update again."
    backup=$(ask_path "Folder for a backup copy, off this Mac if you can (empty to skip)")
    if [ -n "$backup" ]; then
        [ -d "$backup" ] || fail "no folder at $backup"
        cp "$WORK/sparkle.key" "$backup/sparkle-justscribe.key"
        chmod 600 "$backup/sparkle-justscribe.key"
        note "backup written to $backup/sparkle-justscribe.key; move it somewhere safe"
    else
        note "no backup made; do it later with: generate_keys --account $SPARKLE_ACCOUNT -x <file>"
    fi
    rm -f "$WORK/sparkle.key"
else
    note "SPARKLE_PRIVATE_KEY already set"
fi

# --- 4. The website's deploy hook (optional) ----------------------------------
say "Cloudflare deploy hook (optional)"
if wanted CF_DEPLOY_HOOK_URL; then
    note "From the Worker's Settings → Builds → Deploy Hooks (web/README.md). Without it the"
    note "website keeps offering the previous version until it is rebuilt by hand."
    hook=$(ask_hidden "Deploy hook URL (empty to skip)")
    if [ -n "$hook" ]; then
        [[ "$hook" =~ ^https:// ]] || fail "a deploy hook is an https:// URL"
        printf '%s' "$hook" | set_secret CF_DEPLOY_HOOK_URL
    else
        note "skipped"
    fi
else
    note "CF_DEPLOY_HOOK_URL already set"
fi

# --- Summary -----------------------------------------------------------------
say "Secrets on $repo"
existing=$(gh secret list --repo "$repo" --json name --jq '.[].name')
missing=0
for name in MACOS_CERTIFICATE_P12 MACOS_CERTIFICATE_PASSWORD MACOS_SIGNING_IDENTITY APPLE_TEAM_ID \
            ASC_API_KEY_P8 ASC_API_KEY_ID ASC_API_ISSUER_ID SPARKLE_PRIVATE_KEY; do
    if has "$name"; then note "ok       $name"; else note "MISSING  $name"; missing=$((missing + 1)); fi
done
if has CF_DEPLOY_HOOK_URL; then note "ok       CF_DEPLOY_HOOK_URL (optional)"; else note "not set  CF_DEPLOY_HOOK_URL (optional)"; fi
[ "$missing" -eq 0 ] || fail "$missing required secret(s) still missing"
echo
echo "All eight required secrets are set. The next green push to main releases."
