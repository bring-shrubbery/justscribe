#!/bin/bash
# Exercises release-appcast.sh: the fields land where Sparkle reads them, the XML is
# well formed, and a missing option fails. Run: app/Scripts/release-appcast-test.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/release-appcast.sh"
failures=0

ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
printf '<ul>\n  <li>A &amp; B</li>\n  <li>Ends a section ]]> here</li>\n</ul>\n' > "$notes"

out=$("$SCRIPT" --version 1.2.3 --build 45 --tag v1.2.3 \
    --url "https://github.com/bring-shrubbery/justscribe/releases/download/v1.2.3/JustScribe-v1.2.3-macos-arm64.zip" \
    --length 4271794 --signature "AbC+dEf/gH0=" \
    --notes-file "$notes" \
    --notes-link "https://github.com/bring-shrubbery/justscribe/releases/tag/v1.2.3" \
    --date "Sun, 20 Sep 2026 19:19:22 +0000")

if printf '%s' "$out" | xmllint --noout - 2>/dev/null; then ok "well-formed xml"; else fail "xml does not parse"; fi

# check <label> <literal that must appear once>
check() {
    local n
    n=$(printf '%s' "$out" | grep -cF -- "$2" || true)
    if [ "$n" -eq 1 ]; then ok "$1"; else fail "$1 (found $n of: $2)"; fi
}
check "title"          "<title>JustScribe v1.2.3</title>"
check "build number"   "<sparkle:version>45</sparkle:version>"
check "short version"  "<sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>"
check "minimum system" "<sparkle:minimumSystemVersion>26.2</sparkle:minimumSystemVersion>"
check "full notes link" "<sparkle:fullReleaseNotesLink>https://github.com/bring-shrubbery/justscribe/releases/tag/v1.2.3</sparkle:fullReleaseNotesLink>"
check "notes in cdata"  "<description><![CDATA["
check "notes html"      "  <li>A &amp; B</li>"
check "cdata end split" "  <li>Ends a section ]]]]><![CDATA[> here</li>"
if printf '%s' "$out" | grep -q "<sparkle:releaseNotesLink>"; then fail "the old releaseNotesLink must be gone"; else ok "old link gone"; fi
# What Sparkle reads back out of the CDATA is the HTML as written.
if [ "$(printf '%s' "$out" | xmllint --xpath 'string(//item/description)' - | sed '/^[[:space:]]*$/d' | sed 's/^[[:space:]]*//')" = "$(sed 's/^[[:space:]]*//' "$notes")" ]; then ok "description reads back as the notes"; else fail "description does not read back as the notes"; fi
check "pubDate"        "<pubDate>Sun, 20 Sep 2026 19:19:22 +0000</pubDate>"
check "enclosure url"  'url="https://github.com/bring-shrubbery/justscribe/releases/download/v1.2.3/JustScribe-v1.2.3-macos-arm64.zip"'
check "length"         'length="4271794"'
check "type"           'type="application/octet-stream"'
check "signature"      'sparkle:edSignature="AbC+dEf/gH0="'
check "feed link"      "<link>https://justscribe.quassum.com/appcast.xml</link>"
check "one item"       "<item>"

# A missing option is an error, never an empty field.
if "$SCRIPT" --version 1.2.3 --build 45 --tag v1.2.3 --url u --length 1 --notes-file "$notes" --notes-link n --date d >/dev/null 2>&1; then
    fail "missing --signature should fail"
else
    ok "missing --signature fails"
fi
if "$SCRIPT" --version 1.2.3 --build "" --tag v1.2.3 --url u --length 1 --signature s --notes-file "$notes" --notes-link n --date d >/dev/null 2>&1; then
    fail "empty --build should fail"
else
    ok "empty --build fails"
fi
: > "$notes"
if "$SCRIPT" --version 1.2.3 --build 45 --tag v1.2.3 --url u --length 1 --signature s --notes-file "$notes" --notes-link n --date d >/dev/null 2>&1; then
    fail "empty notes should fail"
else
    ok "empty notes fail"
fi

if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi
