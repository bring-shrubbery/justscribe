#!/bin/bash
# Exercises release-notes.sh: subjects are kept as written, documentation commits go, the HTML is
# escaped and well formed. Run: app/Scripts/release-notes-test.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/release-notes.sh"
failures=0
nl=$'\n'

# check <label> <format> <subjects, | separated> <expected output>
check() {
    local label=$1 format=$2 subjects=$3 want=$4 got
    got=$(RELEASE_SUBJECTS="${subjects//|/$nl}" "$SCRIPT" v0.0.0 "$format")
    if [ "$got" = "$want" ]; then
        echo "ok   $label"
    else
        echo "FAIL $label"; printf '  got:\n%s\n  want:\n%s\n' "$got" "$want"
        failures=$((failures + 1))
    fi
}

check "markdown list, oldest first, subjects as written" --markdown \
    "Add a paste command|cut, copy and paste the selection|Fix crash: nil model" \
    "- Add a paste command${nl}- Cut, copy and paste the selection${nl}- Fix crash: nil model"

check "documentation, website and ci commits are left out" --markdown \
    "docs: the design|web: node 24|ci: run on node 24|An audition is heard|chore: the release signs the zip" \
    "- An audition is heard${nl}- Chore: the release signs the zip"

check "nothing left is a maintenance release" --markdown \
    "docs: only" \
    "- Maintenance release."

check "html list, escaped" --html \
    "Add a <T> helper & more|Paste" \
    "<ul>${nl}  <li>Add a &lt;T&gt; helper &amp; more</li>${nl}  <li>Paste</li>${nl}</ul>"

out=$(RELEASE_SUBJECTS="Add a <T> helper & more" "$SCRIPT" v0.0.0 --html)
if printf '%s' "$out" | xmllint --noout - 2>/dev/null; then echo "ok   html is well-formed xml"; else echo "FAIL html does not parse"; failures=$((failures + 1)); fi

if "$SCRIPT" v0.0.0 >/dev/null 2>&1; then
    echo "FAIL a missing format should fail"; failures=$((failures + 1))
else
    echo "ok   missing format fails"
fi

# With no previous tag the real repo's history is listed; it is non-empty.
if [ -n "$("$SCRIPT" "" --markdown)" ]; then
    echo "ok   no previous tag -> whole history"
else
    echo "FAIL no previous tag should list the history"; failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi
