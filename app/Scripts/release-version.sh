#!/bin/bash
# Prints the version the next release gets: the higher of MARKETING_VERSION in
# project.pbxproj (the floor a maintainer raises for a minor or major release)
# and the highest v<major>.<minor>.<patch> tag with its patch + 1. With no such
# tag the pbxproj version is it. Pre-release tags (v1.0.0-checkpoint) are ignored.
#
#   release-version.sh             1.0.3
#   release-version.sh --previous  v1.0.2   (the highest release tag; empty when none)
#
# RELEASE_TAGS (one tag per line) replaces `git tag`, RELEASE_PBXPROJ replaces the
# project file; release-version-test.sh uses both.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PBXPROJ=${RELEASE_PBXPROJ:-"$ROOT/justscribe.xcodeproj/project.pbxproj"}

tags() {
    if [ -n "${RELEASE_TAGS+x}" ]; then printf '%s\n' "$RELEASE_TAGS"; else git -C "$ROOT" tag; fi
}

# Sorts x.y.z lines numerically, lowest first.
sort_versions() {
    sort -t. -k1,1n -k2,2n -k3,3n
}

# The highest strict release tag, without its v; empty when there is none.
highest_release() {
    tags | sed -n 's/^v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p' | sort_versions | tail -1
}

# MARKETING_VERSION from the pbxproj; every configuration must agree.
pbxproj_version() {
    local versions
    versions=$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$PBXPROJ" | sort -u)
    if [ "$(printf '%s\n' "$versions" | grep -c .)" -ne 1 ]; then
        echo "error: expected exactly one MARKETING_VERSION in $PBXPROJ, found: ${versions:-none}" >&2
        exit 1
    fi
    if ! [[ "$versions" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "error: MARKETING_VERSION must be major.minor.patch, found: $versions" >&2
        exit 1
    fi
    echo "$versions"
}

previous=$(highest_release)

if [ "${1:-}" = "--previous" ]; then
    [ -n "$previous" ] && echo "v$previous"
    exit 0
fi

floor=$(pbxproj_version)
if [ -z "$previous" ]; then
    echo "$floor"
    exit 0
fi

IFS=. read -r major minor patch <<< "$previous"
next="$major.$minor.$((10#$patch + 1))"
printf '%s\n%s\n' "$floor" "$next" | sort_versions | tail -1
