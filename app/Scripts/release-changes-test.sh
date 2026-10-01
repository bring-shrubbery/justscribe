#!/bin/bash
# Exercises the docs-only filter in release-changes.sh. Run: app/Scripts/release-changes-test.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/release-changes.sh"
failures=0
nl=$'\n'

# check <label> <paths, space separated> <expected output, space separated>
check() {
    local label=$1 paths=$2 want=$3 got
    got=$(RELEASE_PATHS="${paths// /$nl}" "$SCRIPT" v0.0.0 | tr '\n' ' ' | sed 's/ $//')
    if [ "$got" = "$want" ]; then
        echo "ok   $label -> [${got}]"
    else
        echo "FAIL $label -> got [${got}], want [${want}]"
        failures=$((failures + 1))
    fi
}

check "docs only"        "docs/superpowers/specs/x.md README.md LICENSE CLAUDE.md .gitignore .github/FUNDING.yml .github/ISSUE_TEMPLATE/bug_report.md" ""
check "app source"       "app/justscribe/AppDelegate.swift README.md" "app/justscribe/AppDelegate.swift"
check "workflow"         ".github/workflows/ci.yml .github/FUNDING.yml" ".github/workflows/ci.yml"
check "project file"     "app/justscribe.xcodeproj/project.pbxproj" "app/justscribe.xcodeproj/project.pbxproj"
check "script"           "app/Scripts/release-notes.sh docs/release.md" "app/Scripts/release-notes.sh"
check "md under app"     "app/README.md app/justscribe/Info.plist" "app/justscribe/Info.plist"
check "nothing"          "" ""
check "website"          "web/src/pages/index.astro web/package.json" ""
check "website and app"  "web/src/pages/index.astro app/justscribe/AppDelegate.swift" "app/justscribe/AppDelegate.swift"
check "design assets"    "icon-composer/justscribe.icon/icon.json screenshots/raw/a.png" ""

# With no previous tag every tracked path counts; the real repo has code, so output is non-empty.
if [ -n "$("$SCRIPT" "")" ]; then
    echo "ok   no previous tag -> whole tree"
else
    echo "FAIL no previous tag should list the tree"; failures=$((failures + 1))
fi

# An unknown tag is an error, never "nothing to release".
if "$SCRIPT" no-such-tag-0000 >/dev/null 2>&1; then
    echo "FAIL an unknown tag should exit non-zero"; failures=$((failures + 1))
else
    echo "ok   unknown tag exits non-zero"
fi

if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi
