#!/bin/bash
# Prints the paths changed since the previous release tag that are worth a
# release, one per line; prints nothing when only documentation changed.
# A git query that fails (an unknown tag) exits non-zero; the workflow must stop,
# not treat it as nothing to release.
#
#   release-changes.sh v1.0.2   paths changed between v1.0.2 and HEAD
#   release-changes.sh ""       every tracked path (no release exists yet)
#
# Documentation is docs/, the website under web/, the design sources under
# icon-composer/ and screenshots/, any *.md, LICENSE, .gitignore and .github/
# except the workflows. RELEASE_PATHS (one path per line) replaces the git
# query; the test uses it.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
previous=${1-}

changed_paths() {
    if [ -n "${RELEASE_PATHS+x}" ]; then
        printf '%s\n' "$RELEASE_PATHS"
    elif [ -n "$previous" ]; then
        git -C "$ROOT" diff --name-only "$previous" HEAD
    else
        git -C "$ROOT" ls-tree -r --full-tree --name-only HEAD
    fi
}

is_documentation() {
    case "$1" in
        docs/*|web/*|icon-composer/*|screenshots/*|*.md|LICENSE|.gitignore) return 0 ;;
        .github/workflows/*) return 1 ;;
        .github/*) return 0 ;;
    esac
    return 1
}

changed_paths | while IFS= read -r path; do
    [ -n "$path" ] || continue
    is_documentation "$path" || echo "$path"
done
