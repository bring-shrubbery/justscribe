#!/bin/bash
# Exercises release-sparkle-public-key.swift with throwaway keys; never the real one.
# Run: app/Scripts/release-sparkle-public-key-test.sh
#
# Needs macOS (CryptoKit). Elsewhere it skips, so the Linux job that runs every
# release-*-test.sh passes over it; CI runs it in the macOS app job.
#
# The derived key is checked against RFC 8032's first Ed25519 test vector and, when
# SPARKLE_SIGN_UPDATE points at Sparkle's sign_update, against a signature that tool
# makes with a random seed.
set -euo pipefail

if [ "$(uname -s)" != Darwin ] || ! command -v xcrun > /dev/null; then
    echo "skip: release-sparkle-public-key.swift needs macOS (CryptoKit)"
    exit 0
fi

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/release-sparkle-public-key.swift"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
failures=0

derive() { xcrun swift "$SCRIPT" "$@"; }
hex_to_base64() { xxd -r -p <<< "$1" | base64; }

ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; failures=$((failures + 1)); }

# 1. RFC 8032 §7.1, TEST 1: the seed's public key is fixed by the standard.
hex_to_base64 9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60 > "$TMP/rfc.key"
want=$(hex_to_base64 d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a)
got=$(derive "$TMP/rfc.key")
if [ "$got" = "$want" ]; then ok "RFC 8032 test 1 -> $got"; else bad "RFC 8032 test 1 -> got $got, want $want"; fi

# A trailing newline (as `gh secret set < file` or an editor may leave) is accepted.
printf '%s\n' "$(cat "$TMP/rfc.key")" > "$TMP/rfc-newline.key"
got=$(derive "$TMP/rfc-newline.key")
if [ "$got" = "$want" ]; then ok "trailing newline accepted"; else bad "trailing newline -> got $got, want $want"; fi

# 2. A random seed, signed by Sparkle's own tool, verifies against the derived key.
if [ -n "${SPARKLE_SIGN_UPDATE:-}" ]; then
    head -c 32 /dev/urandom | base64 > "$TMP/random.key"
    public=$(derive "$TMP/random.key")
    head -c 4096 /dev/urandom > "$TMP/update.zip"
    # --ed-key-file always: without it sign_update reads the login keychain.
    signature=$("$SPARKLE_SIGN_UPDATE" --ed-key-file "$TMP/random.key" -p "$TMP/update.zip")
    cat > "$TMP/verify.swift" <<'SWIFT'
import CryptoKit
import Foundation
let args = CommandLine.arguments
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: args[1])!)
let valid = key.isValidSignature(Data(base64Encoded: args[2])!, for: try Data(contentsOf: URL(fileURLWithPath: args[3])))
print(valid ? "valid" : "invalid")
SWIFT
    verdict=$(xcrun swift "$TMP/verify.swift" "$public" "$signature" "$TMP/update.zip")
    if [ "$verdict" = valid ]; then ok "sign_update signature verifies with $public"; else bad "sign_update signature does not verify with $public"; fi
else
    echo "skip sign_update round trip (set SPARKLE_SIGN_UPDATE to Sparkle's bin/sign_update)"
fi

# 3. Anything but a base64 32-byte seed is refused with a message and a non-zero exit.
# expect_failure <label> <message fragment> <args...>
expect_failure() {
    local label=$1 fragment=$2 out status
    shift 2
    set +e
    out=$(derive "$@" 2>&1)
    status=$?
    set -e
    if [ "$status" -ne 0 ] && grep -qF -- "$fragment" <<< "$out"; then
        ok "$label -> exit $status: $out"
    else
        bad "$label -> exit $status: $out (want non-zero and '$fragment')"
    fi
}
head -c 64 /dev/urandom | base64 > "$TMP/long.key"
head -c 96 /dev/urandom | base64 > "$TMP/legacy.key"
head -c 31 /dev/urandom | base64 > "$TMP/short.key"
echo 'not base64!' > "$TMP/garbage.key"
: > "$TMP/empty.key"
expect_failure "64-byte key" "64 bytes" "$TMP/long.key"
expect_failure "96-byte legacy key" "96 bytes" "$TMP/legacy.key"
expect_failure "31-byte key" "31 bytes" "$TMP/short.key"
expect_failure "not base64" "not base64" "$TMP/garbage.key"
expect_failure "empty file" "0 bytes" "$TMP/empty.key"
expect_failure "missing file" "cannot read" "$TMP/missing.key"
expect_failure "no argument" "usage"

if [ "$failures" -gt 0 ]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "all passed"
