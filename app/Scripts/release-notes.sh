#!/bin/bash
# Prints the release notes for the commits since the previous release tag: one line per
# commit subject, oldest first, as written, with the first letter raised.
# Commits to the documentation, the website and CI (`docs:`, `web:`, `ci:`) change nothing
# in the app and are left out. A release with nothing left says "Maintenance release."
#
#   release-notes.sh v1.0.2 --html       an <ul> for the appcast's <description>
#   release-notes.sh v1.0.2 --markdown   a list for the GitHub release body
#   release-notes.sh "" --html           every commit (no release exists yet)
#
# RELEASE_SUBJECTS (one subject per line, oldest first) replaces the git query; the test
# uses it.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
previous=${1-}
format=${2-}

case "$format" in
    --html|--markdown) ;;
    *) echo "usage: release-notes.sh <previous-tag or \"\"> --html|--markdown" >&2; exit 1 ;;
esac

subjects() {
    if [ -n "${RELEASE_SUBJECTS+x}" ]; then
        printf '%s\n' "$RELEASE_SUBJECTS"
    elif [ -n "$previous" ]; then
        git -C "$ROOT" log --first-parent --no-merges --reverse --format=%s "$previous..HEAD"
    else
        git -C "$ROOT" log --first-parent --no-merges --reverse --format=%s HEAD
    fi
}

# The subject, capitalised; nothing for a commit the app never sees.
entry() {
    local subject=$1
    case "$subject" in
        docs:*|web:*|ci:*) return 0 ;;
    esac
    subject=${subject#"${subject%%[![:space:]]*}"}
    [ -n "$subject" ] || return 0
    printf '%s\n' "$(printf '%s' "${subject:0:1}" | tr '[:lower:]' '[:upper:]')${subject:1}"
}

escape_html() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

entries=$(subjects | while IFS= read -r subject; do
    [ -n "$subject" ] || continue
    entry "$subject"
done)

[ -n "$entries" ] || entries="Maintenance release."

if [ "$format" = "--html" ]; then
    echo "<ul>"
    printf '%s\n' "$entries" | escape_html | sed 's/.*/  <li>&<\/li>/'
    echo "</ul>"
else
    printf '%s\n' "$entries" | sed 's/.*/- &/'
fi
