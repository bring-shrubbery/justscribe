# Direct Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** JustScribe ships as a Developer ID signed, notarized DMG from GitHub releases, cut automatically from `main`, offered on `justscribe.quassum.com`, and updates itself through Sparkle.

**Architecture:** The repository takes neural-sheet's shape (`app/`, `web/`, `docs/`). The app loses StoreKit and gains a sandboxed Sparkle updater behind one `UpdateService`. Shell scripts in `app/Scripts/` hold every release decision (version, change filter, notes, appcast, re-signing) so the workflow stays declarative and each decision is testable locally. The site is neural-sheet's Astro project with new content.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, Sparkle 2.10, GitHub Actions (`macos-26`), bash, Astro 7 + Vitest, Cloudflare Workers static assets.

**Spec:** `docs/superpowers/specs/2026-10-01-direct-distribution-design.md`

**Reference project:** `../neural-sheet` (absolute: `/Users/antoni/Projects/neural-sheet`). Several steps copy a file from it and apply exact substitutions. Never edit neural-sheet.

## Global Constraints

- Branch: `direct-distribution`. Never commit to `main` and never push without the maintainer's say-so — once `release.yml` is on `main`, every code commit there ships.
- Commit after each task (the maintainer's standing auto-commit rule). End every commit message with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Never stage anything under `xcuserdata/`.
- The app target must build and the unit tests must pass at the end of every task (tests cannot compile if the app target does not).
- Bundle ID stays `com.quassum.justscribe`; `PRODUCT_NAME` stays `justscribe` (the bundle is `justscribe.app`). The sandbox stays on.
- Every new Swift file starts with the GPL-3.0 header used across the project (shown in full in each task).
- New files under `justscribe/` are picked up by the synchronized group; the only hand edits to `project.pbxproj` are the ones this plan spells out.
- Exact values: feed `https://justscribe.quassum.com/appcast.xml`; repository `bring-shrubbery/justscribe`; sponsor URL `https://github.com/sponsors/bring-shrubbery`; first version `1.3.0`; release build number `GITHUB_RUN_NUMBER + 100`; minimum system `26.2`; assets `JustScribe-vX.Y.Z-macos-arm64.dmg`, `.zip`, `appcast.xml`; Sparkle tools `2.10.0`, SHA-256 `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`; team `6WCYZER5LX`; identity `Developer ID Application: Quassum MB (6WCYZER5LX)`.
- Build command after Task 2: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -configuration Debug build`. Unit tests: `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests`. Before Task 2 the same without `-project app/justscribe.xcodeproj`.

## Review Focus

1. **A commit subject containing `: ` that is not a `docs:`/`web:`/`ci:` prefix** (e.g. `Fix crash: nil model`) — users must read the whole subject in the update prompt, not `Nil model`. Pinned in Task 3 (`release-notes-test.sh`).
2. **The re-signed app losing its entitlements** — a release whose app is no longer sandboxed opens a fresh data location and silently drops users' models and settings. Pinned in Task 6 (`release-resign.sh` asserts the sandbox and both mach-lookup names after signing; rehearsed locally).
3. **The app launched by the test runner or an Xcode preview starting a real updater** — no Sparkle dialog and no network check during tests. Pinned in Task 4 (`UpdateConfigurationTests`).
4. **GitHub's API throttled or down when the site builds** — the page must still build and the button must link to the Releases page. Pinned in Task 7 (`release.test.ts`).
5. **A push that only touches `web/`, `docs/`, `icon-composer/`, `screenshots/` or Markdown** — must not cut an app release. Pinned in Task 3 (`release-changes-test.sh`).

---

### Task 1: Replace the StoreKit tip jar with a sponsor link

Paths in this task are the pre-move ones (repository root).

**Files:**
- Delete: `justscribe/Services/TipJarService.swift`, `justscribe/Views/Settings/Sections/TipJarSettingsSection.swift`, `Products.storekit`
- Create: `justscribe/Views/Settings/Sections/SupportSettingsSection.swift`, `.github/FUNDING.yml`
- Modify: `justscribe/Views/Settings/SettingsView.swift:73`, `justscribe/Utilities/Constants.swift:30-36`, `justscribe.xcodeproj/project.pbxproj` (lines 40 and 96), `justscribe.xcodeproj/xcshareddata/xcschemes/justscribe.xcscheme:78-80`

**Interfaces:**
- Produces: `Constants.URLs.sponsor: URL`, `struct SupportSettingsSection: View` (no parameters).

- [ ] **Step 1: Delete the StoreKit files**

```bash
git rm justscribe/Services/TipJarService.swift justscribe/Views/Settings/Sections/TipJarSettingsSection.swift Products.storekit
```

- [ ] **Step 2: Remove the `Products.storekit` references**

In `justscribe.xcodeproj/project.pbxproj` delete these two lines entirely:

```
		2AB9EDD52FB8998000034124 /* Products.storekit */ = {isa = PBXFileReference; lastKnownFileType = text; path = Products.storekit; sourceTree = "<group>"; };
```
```
				2AB9EDD52FB8998000034124 /* Products.storekit */,
```

In `justscribe.xcodeproj/xcshareddata/xcschemes/justscribe.xcscheme` delete these three lines:

```xml
      <StoreKitConfigurationFileReference
         identifier = "../../Products.storekit">
      </StoreKitConfigurationFileReference>
```

- [ ] **Step 3: Add the sponsor URL and point the website at the new site**

In `justscribe/Utilities/Constants.swift`, replace the `website` line and add `sponsor` after `support`:

```swift
    enum URLs {
        static let website = URL(string: "https://justscribe.quassum.com")!
        static let privacyPolicy = URL(string: "https://quassum.com/apps/justscribe/privacy")!
        static let termsOfService = URL(string: "https://quassum.com/terms")!
        static let credits = URL(string: "https://quassum.com/apps/justscribe#credits")!
        static let support = URL(string: "https://quassum.com/apps/justscribe#support")!
        static let sponsor = URL(string: "https://github.com/sponsors/bring-shrubbery")!
    }
```

- [ ] **Step 4: Write `justscribe/Views/Settings/Sections/SupportSettingsSection.swift`**

```swift
//
//  SupportSettingsSection.swift
//  justscribe
//
//  Copyright (C) 2026 Quassum MB
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI

struct SupportSettingsSection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsSectionContainer(title: "Support JustScribe") {
            VStack(alignment: .leading, spacing: 12) {
                Text("JustScribe is free and open source. If it saves you time, sponsoring helps keep the project going. Sponsoring unlocks nothing — it's just a thank-you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    openURL(Constants.URLs.sponsor)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                        Text("Sponsor on GitHub")
                    }
                }
                .buttonStyle(.pill)
            }
        }
    }
}
```

If `SettingsSectionContainer(title:content:)` without an accessory does not compile, look at how `LinksSettingsSection` calls it (same form) and match.

- [ ] **Step 5: Use it in `SettingsView.swift`**

Replace `TipJarSettingsSection()` (line 73) with `SupportSettingsSection()`.

- [ ] **Step 6: Add `.github/FUNDING.yml`**

```yaml
github: bring-shrubbery
```

- [ ] **Step 7: Verify nothing references StoreKit, build, test**

```bash
grep -rn -i -E "storekit|TipJar" justscribe justscribeTests justscribe.xcodeproj || echo "clean"
xcodebuild -scheme justscribe -configuration Debug build 2>&1 | tail -5
xcodebuild -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | tail -15
```

Expected: `clean`; `** BUILD SUCCEEDED **`; `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add -A justscribe justscribe.xcodeproj/project.pbxproj justscribe.xcodeproj/xcshareddata .github/FUNDING.yml
git commit -m "Replace the StoreKit tip jar with a GitHub Sponsors link"
```

---

### Task 2: Move the Xcode project into `app/`

**Files:**
- Move: `justscribe.xcodeproj`, `justscribe/`, `justscribeTests/`, `justscribeUITests/` → `app/`
- Create: `.gitignore`
- Modify: `CLAUDE.md`, `README.md`

**Interfaces:**
- Produces: the paths every later task uses — `app/justscribe.xcodeproj`, `app/justscribe/…`, `app/justscribeTests/…`.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
# Xcode
xcuserdata/
*.xcuserstate
DerivedData/
build/
*.dSYM
*.dSYM.zip

# Swift Package Manager
.build/
.swiftpm/

# Agent scratch
.superpowers/

# macOS
.DS_Store

# Website
web/node_modules/
web/dist/
web/.astro/
web/.wrangler/
```

- [ ] **Step 2: Untrack personal Xcode state and move**

```bash
git rm --cached -r justscribe.xcodeproj/xcuserdata
mkdir app
git mv justscribe.xcodeproj justscribe justscribeTests justscribeUITests app/
# untracked xcuserdata does not follow git mv; move what is left behind
[ -d justscribe.xcodeproj ] && rsync -a justscribe.xcodeproj/ app/justscribe.xcodeproj/ && rm -rf justscribe.xcodeproj
git status --short | head -20
```

Expected: only renames (`R`), the new `.gitignore`, and the deleted `xcschememanagement.plist`. `project.pbxproj` shows as a pure rename (no content change).

- [ ] **Step 3: Build and test from the new location**

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -configuration Debug build 2>&1 | tail -5
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`.

- [ ] **Step 4: Update `CLAUDE.md`**

- In the three `xcodebuild` commands add `-project app/justscribe.xcodeproj` right after `xcodebuild`.
- Add a first paragraph under `## Architecture`: "The repository has three parts: `app/` (the Xcode project, sources, tests and release scripts), `web/` (the Astro site served at justscribe.quassum.com) and `docs/`. Source paths below are relative to `app/justscribe/`."
- In "Conventions and gotchas": change "new files under `justscribe/`" to "new files under `app/justscribe/`", change the `IDETemplateMacros.plist` path to `app/justscribe.xcodeproj/xcshareddata/IDETemplateMacros.plist`, and delete the bullet "In-app tips use StoreKit; `Products.storekit` is the local testing configuration."

- [ ] **Step 5: Update `README.md`**

- Icon path: `justscribe/Assets.xcassets/…` → `app/justscribe/Assets.xcassets/…`.
- `[Download here](https://quassum.com/apps/justscribe)` → `[Download here](https://justscribe.quassum.com)`.
- "Open in Xcode" step 2: `Open \`app/justscribe.xcodeproj\`.`
- Support → Website: `https://justscribe.quassum.com`.

- [ ] **Step 6: Commit**

```bash
git add -A .gitignore app CLAUDE.md README.md
git status --short   # nothing under xcuserdata may be staged
git commit -m "Move the Xcode project into app/ and add a .gitignore"
```

---

### Task 3: Release decision scripts

Version, change filter, notes and appcast, each with its test, copied from neural-sheet and adapted. Tests are written first.

**Files:**
- Create: `app/Scripts/release-version.sh`, `release-version-test.sh`, `release-changes.sh`, `release-changes-test.sh`, `release-notes.sh`, `release-notes-test.sh`, `release-appcast.sh`, `release-appcast-test.sh` (all executable)
- Modify: `app/justscribe.xcodeproj/project.pbxproj` (all six `MARKETING_VERSION` lines)

**Interfaces:**
- Produces (used by Task 6's workflow, run from the repository root or `app/`):
  - `app/Scripts/release-version.sh` → prints `X.Y.Z`; `--previous` prints `vX.Y.Z` or nothing.
  - `app/Scripts/release-changes.sh <previous-tag|"">` → release-worthy changed paths, one per line.
  - `app/Scripts/release-notes.sh <previous-tag|""> --html|--markdown`.
  - `app/Scripts/release-appcast.sh --version --build --tag --url --length --signature --notes-file --notes-link --date` → appcast XML on stdout.

- [ ] **Step 1: Copy the four tests and adapt them**

```bash
mkdir -p app/Scripts
NS=/Users/antoni/Projects/neural-sheet/app/Scripts
cp $NS/release-version-test.sh $NS/release-changes-test.sh $NS/release-notes-test.sh $NS/release-appcast-test.sh app/Scripts/
```

`release-version-test.sh`: change the header comment's second line to `# docs/release.md. Run: app/Scripts/release-version-test.sh`. Nothing else.

`release-changes-test.sh`: replace the nine `check` lines with:

```bash
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
```

`release-notes-test.sh`: change the header comment to `# Exercises release-notes.sh: subjects are kept as written, documentation commits go, the HTML is` and replace the first three `check` calls (down to and including "a subject without an area is kept as it is") with:

```bash
check "markdown list, oldest first, subjects as written" --markdown \
    "Add a paste command|cut, copy and paste the selection|Fix crash: nil model" \
    "- Add a paste command${nl}- Cut, copy and paste the selection${nl}- Fix crash: nil model"

check "documentation, website and ci commits are left out" --markdown \
    "docs: the design|web: node 24|ci: run on node 24|An audition is heard|chore: the release signs the zip" \
    "- An audition is heard${nl}- Chore: the release signs the zip"
```

and in the two HTML cases replace the subjects and expectations so no `core:`/`app:` prefix stripping is assumed:

```bash
check "html list, escaped" --html \
    "Add a <T> helper & more|Paste" \
    "<ul>${nl}  <li>Add a &lt;T&gt; helper &amp; more</li>${nl}  <li>Paste</li>${nl}</ul>"

out=$(RELEASE_SUBJECTS="Add a <T> helper & more" "$SCRIPT" v0.0.0 --html)
```

`release-appcast-test.sh`:

```bash
sed -i '' -e 's/NeuralSheet/JustScribe/g' -e 's#bring-shrubbery/neural-sheet#bring-shrubbery/justscribe#g' \
  -e 's#neural-sheet\.quassum\.com#justscribe.quassum.com#g' \
  -e 's#<sparkle:minimumSystemVersion>26\.0<#<sparkle:minimumSystemVersion>26.2<#' app/Scripts/release-appcast-test.sh
```

- [ ] **Step 2: Run the tests; they must fail**

```bash
for t in app/Scripts/release-*-test.sh; do "$t" || echo "FAILED: $t"; done
```

Expected: each fails (`No such file or directory` for the script under test).

- [ ] **Step 3: Copy the four scripts and adapt them**

```bash
cp $NS/release-version.sh $NS/release-changes.sh $NS/release-notes.sh $NS/release-appcast.sh app/Scripts/
chmod +x app/Scripts/*.sh
sed -i '' 's#NeuralSheet\.xcodeproj#justscribe.xcodeproj#' app/Scripts/release-version.sh
sed -i '' -e 's/NeuralSheet/JustScribe/g' -e 's#neural-sheet\.quassum\.com#justscribe.quassum.com#g' \
  -e 's/^MINIMUM_SYSTEM="26.0"/MINIMUM_SYSTEM="26.2"/' \
  -e 's#Releases of JustScribe, the audio-to-MIDI transcription app for macOS\.#Releases of JustScribe, on-device voice dictation for macOS.#' \
  app/Scripts/release-appcast.sh
```

`release-changes.sh`: `ROOT` must be the repository root for nothing here (the git commands only need to run inside the repo), so leave it. Replace `is_documentation` and the header comment's documentation sentence:

```bash
# Documentation is docs/, the website under web/, the design sources under
# icon-composer/ and screenshots/, any *.md, LICENSE, .gitignore and .github/
# except the workflows. RELEASE_PATHS (one path per line) replaces the git
# query; the test uses it.
```

```bash
is_documentation() {
    case "$1" in
        docs/*|web/*|icon-composer/*|screenshots/*|*.md|LICENSE|.gitignore) return 0 ;;
        .github/workflows/*) return 1 ;;
        .github/*) return 0 ;;
    esac
    return 1
}
```

`release-notes.sh`: replace the header's first paragraph and the `entry` function so only the three prefixes are special:

```bash
# Prints the release notes for the commits since the previous release tag: one line per
# commit subject, oldest first, as written, with the first letter raised.
# Commits to the documentation, the website and CI (`docs:`, `web:`, `ci:`) change nothing
# in the app and are left out. A release with nothing left says "Maintenance release."
```

```bash
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
```

Also in `subjects()`, add `--no-merges` to both `git log` invocations (after `--first-parent`).

- [ ] **Step 4: Set the version floor**

```bash
sed -i '' -E 's/MARKETING_VERSION = [0-9.]+;/MARKETING_VERSION = 1.3.0;/' app/justscribe.xcodeproj/project.pbxproj
grep -c "MARKETING_VERSION = 1.3.0;" app/justscribe.xcodeproj/project.pbxproj
```

Expected: `6`. (All six configurations, test targets included: `release-version.sh` requires them to agree.)

- [ ] **Step 5: Run the tests; they must pass, and lint**

```bash
for t in app/Scripts/release-*-test.sh; do "$t" | tail -1; done
shellcheck app/Scripts/*.sh
app/Scripts/release-version.sh; app/Scripts/release-version.sh --previous; app/Scripts/release-changes.sh "" | head -3
```

Expected: four `all passed`; shellcheck silent; `1.3.0`; an empty line's worth of nothing for `--previous`; some `app/…` paths.

- [ ] **Step 6: Build (the project file changed) and commit**

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -configuration Debug build 2>&1 | tail -3
git add app/Scripts app/justscribe.xcodeproj/project.pbxproj
git commit -m "Add the release scripts and set the version to 1.3.0"
```

---

### Task 4: Sparkle updater in the app

**Files:**
- Modify: `app/justscribe.xcodeproj/project.pbxproj`, `app/justscribe.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (regenerated), `app/justscribe/Info.plist`, `app/justscribe/justscribe.entitlements`, `app/justscribe/AppDelegate.swift`, `app/justscribe/Views/Settings/SettingsView.swift`
- Create: `app/justscribe/Services/UpdateService.swift`, `app/justscribe/Views/Settings/Sections/UpdateSettingsSection.swift`
- Test: `app/justscribeTests/UpdateConfigurationTests.swift`

**Interfaces:**
- Produces:
  - `UpdateService.shared` (`@MainActor @Observable final class`): `private(set) var canCheckForUpdates: Bool`, `var automaticallyInstallsUpdates: Bool`, `func checkForUpdates()`, `nonisolated static func shouldStartUpdater(environment: [String: String]) -> Bool`.
  - `struct UpdateSettingsSection: View` (no parameters).
  - Info.plist keys `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`, `SUEnableInstallerLauncherService`.

- [ ] **Step 1: Generate the Sparkle key pair (needs the maintainer at the keyboard)**

This writes a private key into the maintainer's login keychain; macOS may ask to allow it. Do not run it twice — a second run prints the existing key, which is fine, but never pass `-f`/`--force`.

```bash
T=$(mktemp -d) && cd "$T"
curl -fsSL -o Sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz
echo "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c  Sparkle.tar.xz" | shasum -a 256 -c -
tar -xJf Sparkle.tar.xz bin/generate_keys
./bin/generate_keys --account JustScribe
cd - >/dev/null
```

Expected: output containing `<key>SUPublicEDKey</key>` and a 44-character base64 `<string>`. Record that string as `PUBLIC_KEY` for Step 4. Leave `$T/bin/generate_keys` in place; Task 8 uses it to export the private key.

- [ ] **Step 2: Write the failing test `app/justscribeTests/UpdateConfigurationTests.swift`**

```swift
//
//  UpdateConfigurationTests.swift
//  justscribeTests
//
//  Copyright (C) 2026 Quassum MB
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
import Testing
@testable import justscribe

struct UpdateConfigurationTests {

    // The tests run inside the app, so Bundle.main is justscribe.app.
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    @Test func feedIsTheWebsiteAppcastOverHTTPS() {
        #expect(info["SUFeedURL"] as? String == "https://justscribe.quassum.com/appcast.xml")
    }

    @Test func publicKeyIsAnEd25519Key() throws {
        let key = try #require(info["SUPublicEDKey"] as? String)
        let data = try #require(Data(base64Encoded: key))
        #expect(data.count == 32)
    }

    @Test func checksAndInstallsAutomaticallyByDefault() {
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == true)
    }

    @Test func sandboxedInstallerServiceIsEnabled() {
        #expect(info["SUEnableInstallerLauncherService"] as? Bool == true)
    }

    @Test func updaterDoesNotStartUnderTheTestRunner() {
        #expect(UpdateService.shouldStartUpdater(environment: ["XCTestConfigurationFilePath": "/tmp/x"]) == false)
    }

    @Test func updaterDoesNotStartInPreviews() {
        #expect(UpdateService.shouldStartUpdater(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]) == false)
    }

    @Test func updaterStartsInANormalLaunch() {
        #expect(UpdateService.shouldStartUpdater(environment: ["HOME": "/Users/x"]) == true)
    }

    @Test func thisTestProcessWouldNotStartTheUpdater() {
        #expect(UpdateService.shouldStartUpdater(environment: ProcessInfo.processInfo.environment) == false)
    }
}
```

- [ ] **Step 3: Run it; it must fail to compile**

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "error:|TEST" | head
```

Expected: `error: cannot find 'UpdateService' in scope`.

- [ ] **Step 4: Add the Sparkle package to `project.pbxproj`**

Four insertions, each next to its siblings (IDs chosen to continue the file's `AA000…` series; confirm none is already present with `grep -c AA0001072F25000000000007 …` → `0`).

In `/* Begin PBXBuildFile section */`, after the `MLXLMCommon in Frameworks` line:

```
		AA0003082F25000000000008 /* Sparkle in Frameworks */ = {isa = PBXBuildFile; productRef = AA0002082F25000000000008 /* Sparkle */; };
```

In the app target's `PBXFrameworksBuildPhase` (`2A2572132F2427780015D8A4`) `files`, after `AA0003072F25000000000007 /* MLXLMCommon in Frameworks */,`:

```
				AA0003082F25000000000008 /* Sparkle in Frameworks */,
```

In the `justscribe` target's `packageProductDependencies`, after `AA0002072F25000000000007 /* MLXLMCommon */,`:

```
				AA0002082F25000000000008 /* Sparkle */,
```

In the project's `packageReferences`, after the `mlx-swift-lm` line:

```
				AA0001072F25000000000007 /* XCRemoteSwiftPackageReference "Sparkle" */,
```

Before `/* End XCRemoteSwiftPackageReference section */`:

```
		AA0001072F25000000000007 /* XCRemoteSwiftPackageReference "Sparkle" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/sparkle-project/Sparkle";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 2.10.0;
			};
		};
```

Before `/* End XCSwiftPackageProductDependency section */`:

```
		AA0002082F25000000000008 /* Sparkle */ = {
			isa = XCSwiftPackageProductDependency;
			package = AA0001072F25000000000007 /* XCRemoteSwiftPackageReference "Sparkle" */;
			productName = Sparkle;
		};
```

Then resolve:

```bash
plutil -lint app/justscribe.xcodeproj/project.pbxproj
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -resolvePackageDependencies 2>&1 | tail -5
grep -A3 -i '"sparkle"' app/justscribe.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved | head -8
```

Expected: `OK`; Sparkle at 2.10.0 or later appears in `Package.resolved`.

- [ ] **Step 5: Fill `app/justscribe/Info.plist`** (replace `PUBLIC_KEY` with the string from Step 1)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- Sparkle. The rest of the Info.plist is generated from build settings and merged with this. -->
	<key>SUFeedURL</key>
	<string>https://justscribe.quassum.com/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string>PUBLIC_KEY</string>
	<key>SUEnableAutomaticChecks</key>
	<true/>
	<key>SUAutomaticallyUpdate</key>
	<true/>
	<!-- The app is sandboxed: Sparkle installs through its XPC launcher service. -->
	<key>SUEnableInstallerLauncherService</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 6: Add the mach-lookup exception to `app/justscribe/justscribe.entitlements`**

Insert before `</dict>`:

```xml
	<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
	<array>
		<string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
		<string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
	</array>
```

- [ ] **Step 7: Write `app/justscribe/Services/UpdateService.swift`**

```swift
//
//  UpdateService.swift
//  justscribe
//
//  Copyright (C) 2026 Quassum MB
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
import Sparkle

/// The in-app updater. One Sparkle controller for the app's lifetime: it reads the feed named
/// by `SUFeedURL` in Info.plist on launch and then daily, shows its own dialogs, and installs
/// in the background unless the user turns that off. The rest of the app never sees Sparkle.
@MainActor
@Observable
final class UpdateService {
    static let shared = UpdateService()

    /// False while a check or an install is under way; "Check for Updates…" is disabled then.
    private(set) var canCheckForUpdates = false

    /// Download and install new versions without asking. Sparkle persists the choice itself
    /// (it is not an `AppSettings` field); the default comes from `SUAutomaticallyUpdate`.
    var automaticallyInstallsUpdates: Bool {
        didSet {
            guard automaticallyInstallsUpdates != oldValue else { return }
            controller.updater.automaticallyDownloadsUpdates = automaticallyInstallsUpdates
        }
    }

    private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// A real updater must not run inside the unit-test host or an Xcode preview: it would
    /// hit the network and could put up Sparkle's alert.
    nonisolated static func shouldStartUpdater(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
            && environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
    }

    private init() {
        let start = Self.shouldStartUpdater(environment: ProcessInfo.processInfo.environment)
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyInstallsUpdates = controller.updater.automaticallyDownloadsUpdates
        canCheckForUpdates = controller.updater.canCheckForUpdates
        // Sparkle drives its updater on the main thread, so the change lands on the main actor.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = change.newValue ?? false
            }
        }
    }

    /// Sparkle reports the outcome itself, including "You're up to date".
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
```

- [ ] **Step 8: Wire the status-item menu in `app/justscribe/AppDelegate.swift`**

In `applicationDidFinishLaunching`, add as the last line:

```swift
        _ = UpdateService.shared // starts Sparkle's scheduled checks
```

In `setupStatusBar()`, between the `Settings...` item and the separator before `Quit JustScribe`:

```swift
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: ""))
```

Next to `openSettings()`:

```swift
    @objc private func checkForUpdatesFromMenu() {
        // A menu-bar app is usually not frontmost; Sparkle's window must not open behind others.
        NSApp.activate(ignoringOtherApps: true)
        UpdateService.shared.checkForUpdates()
    }
```

At the end of the file (outside the class):

```swift
extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdatesFromMenu) {
            return UpdateService.shared.canCheckForUpdates
        }
        return true
    }
}
```

If the compiler rejects the `#selector` of a `private` method from the extension, change `checkForUpdatesFromMenu` to `fileprivate`.

- [ ] **Step 9: Write `app/justscribe/Views/Settings/Sections/UpdateSettingsSection.swift`**

```swift
//
//  UpdateSettingsSection.swift
//  justscribe
//
//  Copyright (C) 2026 Quassum MB
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI

struct UpdateSettingsSection: View {
    private var service: UpdateService { .shared }

    var body: some View {
        SettingsSectionContainer(title: "Updates") {
            VStack(spacing: 12) {
                ToggleSettingsRow(
                    title: "Automatically install updates",
                    subtitle: "New versions download in the background and install when JustScribe quits",
                    systemImage: "arrow.down.circle",
                    isOn: Binding(
                        get: { service.automaticallyInstallsUpdates },
                        set: { service.automaticallyInstallsUpdates = $0 }
                    )
                )

                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check for Updates")
                            .font(.body)
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Check Now") {
                        service.checkForUpdates()
                    }
                    .buttonStyle(.pill)
                    .disabled(!service.canCheckForUpdates)
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
```

In `SettingsView.swift`, between `BehaviorSettingsSection(settings: settings)` and `SupportSettingsSection()`, add:

```swift

                        Divider()

                        UpdateSettingsSection()
```

(so the order is Behavior, Divider, Updates, Divider, Support).

- [ ] **Step 10: Build, test, check the resolved entitlements**

```bash
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | grep -E "error:|warning: .*justscribe/|Test run|TEST" | tail -15
APP=$(xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/justscribe.app
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - | grep -E "app-sandbox|spks|spki"
ls "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
```

Expected: `** TEST SUCCEEDED **` with the eight new tests passing; three lines showing `app-sandbox => true`, `com.quassum.justscribe-spks`, `com.quassum.justscribe-spki`; `Downloader.xpc` and `Installer.xpc` listed.

- [ ] **Step 11: Run the app once and check for updates by hand**

```bash
open "$APP"
```

Click the menu-bar icon → "Check for Updates…". Expected until the first release exists: Sparkle's "Update Error" dialog (the feed redirects to a release that does not exist yet). What must **not** happen: a crash, or no dialog at all. Open Settings and confirm the Updates section shows the toggle on and the version. Quit the app.

- [ ] **Step 12: Commit**

```bash
git add app/justscribe app/justscribeTests app/justscribe.xcodeproj/project.pbxproj app/justscribe.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "Update in place through Sparkle"
```

---

### Task 5: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: a workflow named exactly `CI` (Task 6's `release.yml` triggers on it by name).

- [ ] **Step 1: Write `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  app:
    name: Build and test the app
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v7
      - name: Select the newest installed Xcode
        run: |
          # shellcheck disable=SC2012
          XCODE=$(ls -d /Applications/Xcode_*.app | sort -V | tail -1)
          echo "using $XCODE"
          sudo xcode-select -s "$XCODE"
          xcodebuild -version
          sw_vers -productVersion
      # mlx-swift compiles Metal shaders; recent Xcode ships the Metal toolchain as a component.
      - name: Install the Metal toolchain
        run: xcodebuild -downloadComponent MetalToolchain || true
      - name: Cache Swift packages
        uses: actions/cache@v6
        with:
          path: ~/Library/Developer/Xcode/DerivedData/**/SourcePackages
          key: spm-${{ runner.os }}-${{ hashFiles('app/justscribe.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
      # Signed ad hoc: the unit tests run inside the sandboxed app, which must carry its entitlements.
      - name: Build and run the unit tests
        run: |
          set -o pipefail
          xcodebuild -project app/justscribe.xcodeproj -scheme justscribe \
            -configuration Debug -destination 'platform=macOS,arch=arm64' \
            -skipPackagePluginValidation -skipMacroValidation \
            CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="" \
            test -only-testing:justscribeTests 2>&1 | tee build.log | tail -40

  scripts:
    name: Release scripts
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - name: Install xmllint
        run: sudo apt-get update -qq && sudo apt-get install -y -qq libxml2-utils
      - name: Run the script tests
        run: |
          for t in app/Scripts/release-*-test.sh; do
            echo "== $t"; "$t"
          done

  web:
    name: Website
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: web
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version-file: web/.nvmrc
          cache: npm
          cache-dependency-path: web/package-lock.json
      - run: npm ci
      - run: npm run check
      - run: npm test
      - run: npm run build
```

Notes for the implementer:
- The scripts and their tests use only bash and POSIX `sed`/`sort`/`grep`, so they should run on Linux; if a script test fails on Ubuntu only (a GNU vs BSD tool difference), move the `scripts` job to `macos-26` rather than rewriting the scripts.
- The `web` job fails until Task 7 lands `web/`; Tasks 5–7 reach `main` together, so this is never observed.

- [ ] **Step 2: Lint and prove the ad-hoc test command locally**

```bash
actionlint .github/workflows/ci.yml
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation \
  -derivedDataPath /private/tmp/justscribe-ci-dd \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="" \
  test -only-testing:justscribeTests 2>&1 | tail -8
rm -rf /private/tmp/justscribe-ci-dd
```

Expected: actionlint silent; `** TEST SUCCEEDED **`. If the ad-hoc signed app refuses to launch as a test host, fall back to `CODE_SIGNING_ALLOWED=NO` with `build` instead of `test` in the workflow, and record in `docs/release.md` (Task 6) that CI is build-only.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: build the app, run the unit tests, the script tests and the website checks"
```

---

### Task 6: Release workflow, re-signing script and `docs/release.md`

**Files:**
- Create: `app/Scripts/release-resign.sh`, `.github/workflows/release.yml`, `docs/release.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: the four scripts from Task 3; the workflow name `CI` from Task 5; the Sparkle layout from Task 4.
- Produces: `app/Scripts/release-resign.sh <path/to/justscribe.app> <signing identity common name>` — re-signs Sparkle's helpers, the framework and the app; exits non-zero unless every helper carries the identity, the app keeps its sandbox and mach-lookup entitlements, and `codesign --verify --deep --strict` passes.

- [ ] **Step 1: Write `app/Scripts/release-resign.sh`** (`chmod +x`)

```bash
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
codesign -d --entitlements - --xml "$APP" > "$ENT" 2>/dev/null
[ -s "$ENT" ] || fail "$APP carries no entitlements to preserve"

sign() { codesign -f -s "$IDENTITY" -o runtime --timestamp "$@"; }
sign "$B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$B/XPCServices/Downloader.xpc"
sign "$B/Autoupdate"
sign "$B/Updater.app"
sign "$FW"
sign --entitlements "$ENT" "$APP"

for item in "$B/Autoupdate" "$B/Updater.app" "$B/XPCServices/Installer.xpc" "$B/XPCServices/Downloader.xpc" "$FW" "$APP"; do
    codesign -dvv "$item" 2>&1 | grep -qF "Authority=$IDENTITY" || fail "$item is not signed by $IDENTITY"
done

signed=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p -)
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
grep -q '"com.apple.security.app-sandbox" => true' <<< "$signed" || fail "the re-signed app is not sandboxed"
for name in "$bundle_id-spks" "$bundle_id-spki"; do
    grep -qF "\"$name\"" <<< "$signed" || fail "the re-signed app lost the mach-lookup entitlement $name"
done

codesign --verify --deep --strict --verbose=2 "$APP"
echo "re-signed $APP as $IDENTITY; sandbox and Sparkle entitlements intact"
```

- [ ] **Step 2: Rehearse the archive and re-sign locally with the real identity**

The Developer ID certificate is in this Mac's keychain (`security find-identity -v -p codesigning` lists it).

```bash
cd app
IDENTITY="Developer ID Application: Quassum MB (6WCYZER5LX)"
xcodebuild -project justscribe.xcodeproj -scheme justscribe -configuration Release \
  -destination 'platform=macOS,arch=arm64' -archivePath build/justscribe.xcarchive \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM=6WCYZER5LX \
  MARKETING_VERSION=1.3.0 CURRENT_PROJECT_VERSION=101 \
  archive 2>&1 | tail -5
Scripts/release-resign.sh build/justscribe.xcarchive/Products/Applications/justscribe.app "$IDENTITY"
defaults read "$PWD/build/justscribe.xcarchive/Products/Applications/justscribe.app/Contents/Info.plist" CFBundleShortVersionString
ls build/justscribe.xcarchive/Products/Applications/justscribe.app/Contents/Resources/ | grep -i icns
cd ..
```

Expected: `** ARCHIVE SUCCEEDED **`; `re-signed … sandbox and Sparkle entitlements intact`; `1.3.0`; `AppIcon.icns`. If the archive fails asking for a provisioning profile, add `PROVISIONING_PROFILE_SPECIFIER=""` to the command here and in the workflow below. `app/build/` is ignored by `.gitignore`.

Negative check — the script must refuse an app that lost its entitlements:

```bash
cp -R app/build/justscribe.xcarchive/Products/Applications/justscribe.app /private/tmp/justscribe-noent.app
codesign -f -s "Developer ID Application: Quassum MB (6WCYZER5LX)" -o runtime /private/tmp/justscribe-noent.app
app/Scripts/release-resign.sh /private/tmp/justscribe-noent.app "Developer ID Application: Quassum MB (6WCYZER5LX)"; echo "exit $?"
rm -rf /private/tmp/justscribe-noent.app
```

Expected: `error: … carries no entitlements to preserve` and `exit 1`.

- [ ] **Step 3: Write `.github/workflows/release.yml`**

```yaml
name: Release

# Every code change that lands on main and passes CI becomes a patch release:
# a signed, notarized JustScribe-vX.Y.Z-macos-arm64.dmg (and zip) on a GitHub
# release, tagged vX.Y.Z. The version is the higher of MARKETING_VERSION in the
# Xcode project and the last release tag's patch + 1; raise MARKETING_VERSION in
# Xcode to ship a minor or major. Changes to docs/, web/, icon-composer/,
# screenshots/, *.md, LICENSE and .github/ (except the workflows) do not release.
# docs/release.md explains the secrets and the flow.

on:
  workflow_run:
    workflows: [CI]
    types: [completed]
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

# Releases queue rather than race: two runs computing the same version would
# fight over the tag.
concurrency:
  group: release
  cancel-in-progress: false

jobs:
  version:
    name: Decide the version
    # Only a green CI run of a push to main (not a pull request build whose head
    # branch happens to be main) or a manual dispatch releases.
    if: >-
      (github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main') ||
      (github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push')
    runs-on: ubuntu-latest
    outputs:
      release: ${{ steps.decide.outputs.release }}
      version: ${{ steps.decide.outputs.version }}
      tag: ${{ steps.decide.outputs.tag }}
      sha: ${{ steps.decide.outputs.sha }}
    steps:
      - uses: actions/checkout@v7
        with:
          # The commit CI built, not main's tip, which may have moved on.
          ref: ${{ github.event.workflow_run.head_sha || github.sha }}
          fetch-depth: 0
      - name: Compare with the last release
        id: decide
        run: |
          previous=$(app/Scripts/release-version.sh --previous)
          changed=$(app/Scripts/release-changes.sh "$previous")
          sha=$(git rev-parse HEAD)
          echo "sha=$sha" >> "$GITHUB_OUTPUT"
          if [ -z "$changed" ]; then
            echo "no code changes since ${previous:-the first commit}; nothing to release"
            echo "release=false" >> "$GITHUB_OUTPUT"
            exit 0
          fi
          version=$(app/Scripts/release-version.sh)
          echo "releasing v$version from $sha (previous release: ${previous:-none}); changed:"
          echo "$changed"
          {
            echo "release=true"
            echo "version=$version"
            echo "tag=v$version"
          } >> "$GITHUB_OUTPUT"

  release:
    name: Build and publish
    needs: version
    if: needs.version.outputs.release == 'true'
    runs-on: macos-26
    permissions:
      contents: write
    env:
      VERSION: ${{ needs.version.outputs.version }}
      TAG: ${{ needs.version.outputs.tag }}
      SHA: ${{ needs.version.outputs.sha }}
    steps:
      - name: Check the signing secrets
        env:
          MACOS_CERTIFICATE_P12: ${{ secrets.MACOS_CERTIFICATE_P12 }}
          MACOS_CERTIFICATE_PASSWORD: ${{ secrets.MACOS_CERTIFICATE_PASSWORD }}
          MACOS_SIGNING_IDENTITY: ${{ secrets.MACOS_SIGNING_IDENTITY }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          ASC_API_KEY_P8: ${{ secrets.ASC_API_KEY_P8 }}
          ASC_API_KEY_ID: ${{ secrets.ASC_API_KEY_ID }}
          ASC_API_ISSUER_ID: ${{ secrets.ASC_API_ISSUER_ID }}
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          missing=()
          for name in MACOS_CERTIFICATE_P12 MACOS_CERTIFICATE_PASSWORD MACOS_SIGNING_IDENTITY \
                      APPLE_TEAM_ID ASC_API_KEY_P8 ASC_API_KEY_ID ASC_API_ISSUER_ID SPARKLE_PRIVATE_KEY; do
            [ -n "${!name}" ] || missing+=("$name")
          done
          if [ "${#missing[@]}" -gt 0 ]; then
            echo "::error::missing repository secrets: ${missing[*]}; see docs/release.md"
            exit 1
          fi
          echo "all signing secrets present"

      - uses: actions/checkout@v7
        with:
          ref: ${{ env.SHA }}
          # The release notes are the commits since the previous tag.
          fetch-depth: 0
      - name: Select the newest installed Xcode
        run: |
          # shellcheck disable=SC2012  # /Applications/Xcode_*.app names are well-known; ls -d | sort -V is intentional.
          XCODE=$(ls -d /Applications/Xcode_*.app | sort -V | tail -1)
          echo "using $XCODE"
          sudo xcode-select -s "$XCODE"
          xcodebuild -version
      # mlx-swift compiles Metal shaders; recent Xcode ships the Metal toolchain as a component.
      - name: Install the Metal toolchain
        run: xcodebuild -downloadComponent MetalToolchain || true

      - name: Import the signing certificate
        env:
          P12: ${{ secrets.MACOS_CERTIFICATE_P12 }}
          P12_PASSWORD: ${{ secrets.MACOS_CERTIFICATE_PASSWORD }}
          IDENTITY: ${{ secrets.MACOS_SIGNING_IDENTITY }}
        run: |
          echo "$P12" | base64 --decode > "$RUNNER_TEMP/cert.p12"
          security create-keychain -p ci build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p ci build.keychain
          security set-keychain-settings -lut 21600 build.keychain
          security import "$RUNNER_TEMP/cert.p12" -k build.keychain -P "$P12_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k ci build.keychain
          rm "$RUNNER_TEMP/cert.p12"
          if ! security find-identity -v -p codesigning build.keychain | tee /dev/stderr | grep -q "$IDENTITY"; then
            echo "::error::the imported certificate does not yield the identity $IDENTITY"; exit 1
          fi

      - name: Archive
        id: archive
        working-directory: app
        env:
          IDENTITY: ${{ secrets.MACOS_SIGNING_IDENTITY }}
          TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          set -o pipefail
          # Above the App Store's last build (8), and monotonic: Sparkle compares this.
          BUILD=$((GITHUB_RUN_NUMBER + 100))
          xcodebuild -project justscribe.xcodeproj -scheme justscribe -configuration Release \
            -destination 'platform=macOS,arch=arm64' -archivePath build/justscribe.xcarchive \
            -skipPackagePluginValidation -skipMacroValidation \
            ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
            CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
            MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
            archive 2>&1 | tee build.log | tail -30
          APP=build/justscribe.xcarchive/Products/Applications/justscribe.app
          Scripts/release-resign.sh "$APP" "$IDENTITY"
          built=$(defaults read "$PWD/$APP/Contents/Info.plist" CFBundleShortVersionString)
          if [ "$built" != "$VERSION" ]; then
            echo "::error::built CFBundleShortVersionString is $built, expected $VERSION"; exit 1
          fi
          build_number=$(defaults read "$PWD/$APP/Contents/Info.plist" CFBundleVersion)
          if [ "$build_number" != "$BUILD" ]; then
            echo "::error::built CFBundleVersion is $build_number, expected $BUILD"; exit 1
          fi
          echo "built $built ($build_number)"
          echo "build_number=$build_number" >> "$GITHUB_OUTPUT"

      - name: Build the disk image
        working-directory: app
        run: |
          brew install create-dmg
          APP=build/justscribe.xcarchive/Products/Applications/justscribe.app
          DMG="build/JustScribe-$TAG-macos-arm64.dmg"
          rm -rf build/dmg-root && mkdir -p build/dmg-root
          cp -R "$APP" build/dmg-root/
          volicon=()
          if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
            volicon=(--volicon "$APP/Contents/Resources/AppIcon.icns")
          fi
          # create-dmg exits 64 with no DMG produced when the Finder AppleScript
          # that lays out the window fails, which happens intermittently on
          # headless runners; retry once without the Finder layout.
          args=(
            --volname "JustScribe $TAG" "${volicon[@]}"
            --window-pos 200 120 --window-size 540 380 --icon-size 128
            --icon justscribe.app 140 180 --app-drop-link 400 180
            --no-internet-enable --hdiutil-quiet
          )
          if ! create-dmg "${args[@]}" "$DMG" build/dmg-root; then
            echo "::warning::create-dmg could not lay out the window; retrying without the Finder layout"
            create-dmg "${args[@]}" --skip-jenkins "$DMG" build/dmg-root
          fi
          ls -l "$DMG"

      - name: Sign, notarize and staple
        working-directory: app
        env:
          IDENTITY: ${{ secrets.MACOS_SIGNING_IDENTITY }}
          ASC_API_KEY_P8: ${{ secrets.ASC_API_KEY_P8 }}
          ASC_API_KEY_ID: ${{ secrets.ASC_API_KEY_ID }}
          ASC_API_ISSUER_ID: ${{ secrets.ASC_API_ISSUER_ID }}
        run: |
          set -o pipefail
          APP=build/justscribe.xcarchive/Products/Applications/justscribe.app
          DMG="build/JustScribe-$TAG-macos-arm64.dmg"
          KEY="$RUNNER_TEMP/AuthKey.p8"
          trap 'rm -f "$KEY"' EXIT
          printf '%s\n' "$ASC_API_KEY_P8" > "$KEY"

          codesign --sign "$IDENTITY" --timestamp "$DMG"
          codesign --verify --verbose=2 "$DMG"

          if ! xcrun notarytool submit "$DMG" --key "$KEY" --key-id "$ASC_API_KEY_ID" \
            --issuer "$ASC_API_ISSUER_ID" --wait --timeout 45m --output-format json \
            | tee build/notarize.json; then
            echo "::warning::notarytool exited non-zero; reading its status"
          fi
          status=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))' < build/notarize.json)
          if [ "$status" != "Accepted" ]; then
            id=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))' < build/notarize.json)
            [ -n "$id" ] && xcrun notarytool log "$id" --key "$KEY" --key-id "$ASC_API_KEY_ID" --issuer "$ASC_API_ISSUER_ID" || true
            echo "::error::notarization ended with status '${status:-unknown}'"
            exit 1
          fi

          # The ticket covers the app inside the image too; staple both so the
          # DMG and the zipped app each work offline.
          xcrun stapler staple "$DMG"
          xcrun stapler staple "$APP"
          spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
          ditto -c -k --keepParent "$APP" "build/JustScribe-$TAG-macos-arm64.zip"

      - name: Sign the update and write the appcast
        working-directory: app
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
          SPARKLE_VERSION: 2.10.0
          SPARKLE_SHA256: c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
        run: |
          set -o pipefail
          ZIP="build/JustScribe-$TAG-macos-arm64.zip"
          KEY="$RUNNER_TEMP/sparkle-key"
          trap 'rm -f "$KEY"' EXIT
          printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY"

          # Sparkle's command-line tools, pinned by version and checksum.
          TOOLS="$RUNNER_TEMP/sparkle"
          mkdir -p "$TOOLS"
          curl -fsSL --retry 3 --retry-all-errors -o "$TOOLS/Sparkle.tar.xz" \
            "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
          echo "$SPARKLE_SHA256  $TOOLS/Sparkle.tar.xz" | shasum -a 256 -c -
          tar -xJf "$TOOLS/Sparkle.tar.xz" -C "$TOOLS" bin/sign_update

          signature=$("$TOOLS/bin/sign_update" --ed-key-file "$KEY" "$ZIP")
          echo "sign_update: $signature"
          ed=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<< "$signature")
          length=$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<< "$signature")
          if [ -z "$ed" ] || [ -z "$length" ]; then
            echo "::error::sign_update did not produce a signature and length"; exit 1
          fi

          # The notes: the commits since the last release, as HTML inside the feed (what the
          # update prompt shows) and as Markdown for the release page.
          previous=$(Scripts/release-version.sh --previous)
          Scripts/release-notes.sh "$previous" --html > build/release-notes.html
          Scripts/release-notes.sh "$previous" --markdown > build/release-notes.md
          {
            echo
            echo "**Full changelog**: https://github.com/$GITHUB_REPOSITORY/compare/${previous:-$(git rev-list --max-parents=0 HEAD | tail -1)}...$TAG"
          } >> build/release-notes.md
          cat build/release-notes.md

          Scripts/release-appcast.sh \
            --version "$VERSION" --build "${{ steps.archive.outputs.build_number }}" --tag "$TAG" \
            --url "https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/JustScribe-$TAG-macos-arm64.zip" \
            --length "$length" --signature "$ed" \
            --notes-file build/release-notes.html \
            --notes-link "https://github.com/$GITHUB_REPOSITORY/releases/tag/$TAG" \
            --date "$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')" > build/appcast.xml
          xmllint --noout build/appcast.xml
          cat build/appcast.xml

      - name: Keep the assets as run artifacts
        uses: actions/upload-artifact@v7
        with:
          name: JustScribe-${{ env.TAG }}-macos-arm64
          path: |
            app/build/JustScribe-${{ env.TAG }}-macos-arm64.dmg
            app/build/JustScribe-${{ env.TAG }}-macos-arm64.zip
            app/build/appcast.xml
          if-no-files-found: error

      - name: Remove the signing keychain
        if: always()
        run: security delete-keychain build.keychain || true

      - name: Tag the commit
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git tag -a "$TAG" -m "JustScribe $TAG" "$SHA"
          git push origin "refs/tags/$TAG"

      - name: Publish the GitHub release
        uses: softprops/action-gh-release@v3
        with:
          tag_name: ${{ env.TAG }}
          target_commitish: ${{ env.SHA }}
          name: JustScribe ${{ env.TAG }}
          body_path: app/build/release-notes.md
          fail_on_unmatched_files: true
          files: |
            app/build/JustScribe-${{ env.TAG }}-macos-arm64.dmg
            app/build/JustScribe-${{ env.TAG }}-macos-arm64.zip
            app/build/appcast.xml

      - name: Rebuild the website
        env:
          CF_DEPLOY_HOOK_URL: ${{ secrets.CF_DEPLOY_HOOK_URL }}
        run: |
          if [ -z "$CF_DEPLOY_HOOK_URL" ]; then
            echo "::warning::CF_DEPLOY_HOOK_URL is not set; the website keeps offering the previous release until it is rebuilt (docs/release.md)"
            exit 0
          fi
          curl -fsS --retry 3 --retry-all-errors -X POST "$CF_DEPLOY_HOOK_URL" -o /dev/null
          echo "website rebuild requested"

      - name: Summary
        if: always()
        run: |
          {
            echo "## JustScribe $TAG"
            echo
            echo "- commit \`$SHA\`"
            echo "- build $((GITHUB_RUN_NUMBER + 100))"
            echo "- https://github.com/$GITHUB_REPOSITORY/releases/tag/$TAG"
          } >> "$GITHUB_STEP_SUMMARY"
```

- [ ] **Step 4: Lint**

```bash
actionlint .github/workflows/release.yml
shellcheck app/Scripts/release-resign.sh
```

Expected: both silent.

- [ ] **Step 5: Write `docs/release.md`**

Start from neural-sheet's and apply the substitutions, then make the edits listed:

```bash
cp /Users/antoni/Projects/neural-sheet/docs/release.md docs/release.md
sed -i '' -e 's/NeuralSheet/JustScribe/g' -e 's#bring-shrubbery/neural-sheet#bring-shrubbery/justscribe#g' \
  -e 's#neural-sheet\.quassum\.com#justscribe.quassum.com#g' -e 's#app/JustScribe\.xcodeproj#app/justscribe.xcodeproj#g' \
  -e 's#target JustScribe#target justscribe#' -e 's#sparkle-neuralsheet\.key#sparkle-justscribe.key#g' \
  -e 's#`app/Info.plist`#`app/justscribe/Info.plist`#g' docs/release.md
grep -n -i "neural" docs/release.md   # must print nothing
```

Edits by hand:
- **Versions**: the build number sentence becomes "The build number (`CURRENT_PROJECT_VERSION`) is the workflow run number + 100, which keeps it above the last App Store build (8)." The ignored-paths bullet lists `docs/`, `web/`, `icon-composer/`, `screenshots/`, `*.md`, `LICENSE`, `.gitignore` and `.github/` (except the workflows). When raising the version in Xcode, say "set it on all three targets — the release stops if they disagree".
- **Release notes paragraph**: replace with "The GitHub release body and the notes the update prompt shows are the commit subjects since the previous tag (`app/Scripts/release-notes.sh`), as written. Commits whose subject starts with `docs:`, `web:` or `ci:` are left out, so use those prefixes for changes users never see, and write every other subject as the line a user will read." Remove the `CHANGELOG.md` sentence.
- **Certificate and API key sections**: add one sentence at the top of "One-time setup": "The Developer ID certificate and the App Store Connect key are the ones neural-sheet uses (team `6WCYZER5LX`); export or reuse the same files and set them on this repository."
- **Sparkle section**: date of generation becomes the day Task 4 Step 1 ran; account name `JustScribe`. Add: "The app is sandboxed, so Sparkle installs through its XPC launcher service (`SUEnableInstallerLauncherService`) and the app carries two mach-lookup entitlements. `app/Scripts/release-resign.sh` re-signs Sparkle's helpers and refuses to continue if the app lost its sandbox or those entitlements."
- **The first release**: remove the sentence about the stem separation library's CMake build; say "about fifteen minutes, most of it Apple's notarization queue". Add a subsection **Leaving the App Store**: "v1.3.0 is the first direct release. Install it over the App Store copy and confirm models and settings are still there (same bundle ID, same sandbox container). macOS asks for Accessibility again because the signature changed: remove the old JustScribe entry in System Settings → Privacy & Security → Accessibility if the toggle has no effect. Only after a later release (v1.3.1) has installed itself through the update prompt: remove the app from sale in App Store Connect and point quassum.com/apps/justscribe at the new site."
- **When it fails**: replace the Sparkle-helper sentence with "A third cause is a Sparkle helper that lost its Developer ID signature, or an app that lost its entitlements; `release-resign.sh` stops with a message naming which." Add a bullet: "**CI is red on the unit tests but the build is fine** — the hosted runner's macOS may be older than the app's deployment target (26.2); the log's `sw_vers` line shows it."

- [ ] **Step 6: Add the release paragraph to `CLAUDE.md`**

After the "Settings persistence" section, add:

```markdown
### Releases and updates

Every push to `main` that passes CI and changes code is released automatically
(`.github/workflows/release.yml`, `app/Scripts/release-*.sh`, `docs/release.md`): commit
subjects become the release notes users read, so prefix changes users never see with
`docs:`, `web:` or `ci:`, and keep unfinished work on a branch. Installed copies update
through Sparkle (`Services/UpdateService.swift`; feed and key in `Info.plist`). The app is
sandboxed, so Sparkle depends on `SUEnableInstallerLauncherService` and the two
mach-lookup entitlements in `justscribe.entitlements` — removing either breaks updates for
every installed copy.
```

- [ ] **Step 7: Commit**

```bash
git add app/Scripts/release-resign.sh .github/workflows/release.yml docs/release.md CLAUDE.md
git commit -m "ci: release every green push to main as a signed, notarized DMG with an appcast"
```

---

### Task 7: Website

**Files:**
- Create under `web/`: `.gitignore`, `.nvmrc`, `package.json`, `package-lock.json`, `tsconfig.json`, `vitest.config.ts`, `astro.config.mjs`, `wrangler.jsonc`, `README.md`, `scripts/og-image.py`, `public/_headers`, `public/_redirects`, `public/robots.txt`, `public/llms.txt`, `public/fonts/*`, `public/icon.png`, `public/favicon.png`, `public/apple-touch-icon.png`, `public/og.png`, `src/assets/icon.png`, `src/assets/screenshot.png`, `src/lib/release.ts`, `src/lib/release.test.ts`, `src/layouts/Base.astro`, `src/components/Download.astro`, `src/pages/index.astro`, `src/pages/404.astro`, `src/styles/global.css`

**Interfaces:**
- Consumes: release asset naming from Task 6 (`…-macos-arm64.dmg`).
- Produces: `web/` building with `npm run build`; `/appcast.xml` redirect that `SUFeedURL` (Task 4) depends on.

- [ ] **Step 1: Copy the scaffold and the test, rename**

```bash
NSW=/Users/antoni/Projects/neural-sheet/web
mkdir -p web/public/fonts web/src/lib web/src/layouts web/src/components web/src/pages web/src/styles web/src/assets web/scripts
cp $NSW/.gitignore $NSW/.nvmrc $NSW/package.json $NSW/package-lock.json $NSW/tsconfig.json $NSW/vitest.config.ts $NSW/astro.config.mjs $NSW/wrangler.jsonc web/
cp $NSW/public/_headers $NSW/public/_redirects $NSW/public/robots.txt web/public/
cp $NSW/public/fonts/* web/public/fonts/
cp $NSW/src/lib/release.test.ts web/src/lib/
cd web
sed -i '' -e 's/neural-sheet-web/justscribe-web/g' -e 's#bring-shrubbery/neural-sheet#bring-shrubbery/justscribe#g' \
  -e 's#neural-sheet\.quassum\.com#justscribe.quassum.com#g' -e 's/NeuralSheet/JustScribe/g' \
  package.json package-lock.json astro.config.mjs wrangler.jsonc public/_redirects public/robots.txt src/lib/release.test.ts
sed -i '' 's/"compatibility_date": "[0-9-]*"/"compatibility_date": "2026-10-01"/' wrangler.jsonc
cd ..
```

Rewrite `web/public/fonts/README.md` to:

```markdown
# Fonts

Inter (Regular, Medium, SemiBold) and JetBrains Mono NL Regular, subset to Latin plus the
symbols the page uses (⌘ ⌥ ⇧ ⌃ · × —) and packed as woff2. Copied from the neural-sheet
website (`../neural-sheet/web/public/fonts`). Licences: Inter-LICENSE.txt,
JetBrainsMono-OFL.txt (both OFL 1.1).
```

The page uses `⌃` (Control, U+2303). Check the subset has it; if this prints `missing`, write the shortcut on the page as `Control` `Shift` `Space` in words instead of symbols:

```bash
python3 - <<'EOF'
from fontTools.ttLib import TTFont
f = TTFont('web/public/fonts/Inter-Regular.woff2')
print('ok' if 0x2303 in f.getBestCmap() else 'missing')
EOF
```

(If `fontTools` is not installed, treat it as `missing` and use words.)

- [ ] **Step 2: Install and run the test; it must fail**

```bash
cd web && npm install && npm test 2>&1 | tail -8; cd ..
```

Expected: FAIL — `Failed to resolve import "./release"`.

- [ ] **Step 3: Add `src/lib/release.ts`**

```bash
cp /Users/antoni/Projects/neural-sheet/web/src/lib/release.ts web/src/lib/release.ts
sed -i '' -e 's#bring-shrubbery/neural-sheet#bring-shrubbery/justscribe#g' -e 's/neural-sheet-web/justscribe-web/g' web/src/lib/release.ts
cd web && npm test 2>&1 | tail -8; cd ..
```

Expected: all tests pass (releaseFrom, fetchLatestRelease incl. 403/404/throw/non-JSON → `null`, formatMegabytes).

- [ ] **Step 4: Assets**

```bash
ICON="icon-composer/macos/Icon-macOS-Default-1024x1024@1x.png"
cp "$ICON" web/src/assets/icon.png
cp "$ICON" web/public/icon.png
sips -z 32 32 "$ICON" --out web/public/favicon.png >/dev/null
sips -z 180 180 "$ICON" --out web/public/apple-touch-icon.png >/dev/null
cp "screenshots/raw/Screenshot 2026-01-30 at 20.45.35.png" web/src/assets/screenshot.png
```

(The screenshot is the notch indicator saying "Listening… Speak now" over a desktop, 1362×889.)

`web/scripts/og-image.py`:

```python
#!/usr/bin/env python3
"""Renders public/og.png (1200x630): the app icon, the name and the tagline on the
site's dark background, in Inter. Run from web/:
  OG_FONTS=../../neural-sheet/app/NeuralSheet/Resources/Fonts python3 scripts/og-image.py
OG_FONTS is a directory holding Inter-SemiBold.ttf, Inter-Regular.ttf and Inter-Medium.ttf
(needs Pillow: pip install pillow)."""
import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

WEB = Path(__file__).resolve().parent.parent
FONTS = Path(os.environ["OG_FONTS"])
W, H = 1200, 630
BG, TEXT, MUTED = (0x0F, 0x12, 0x17), (0xF2, 0xF4, 0xF7), (0x9B, 0xA1, 0xAB)

card = Image.new("RGBA", (W, H), BG + (255,))
icon = Image.open(WEB / "src/assets/icon.png").convert("RGBA")
icon = icon.crop((100, 100, 924, 924)).resize((200, 200), Image.LANCZOS)
card.alpha_composite(icon, (96, 118))

draw = ImageDraw.Draw(card)
name = ImageFont.truetype(str(FONTS / "Inter-SemiBold.ttf"), 76)
lead = ImageFont.truetype(str(FONTS / "Inter-Regular.ttf"), 34)
small = ImageFont.truetype(str(FONTS / "Inter-Medium.ttf"), 26)
draw.text((340, 130), "JustScribe", font=name, fill=TEXT)
draw.text((340, 232), "Hold a key, speak, and the text", font=lead, fill=TEXT)
draw.text((340, 278), "appears in any Mac app.", font=lead, fill=TEXT)
draw.text((96, 470), "Free  ·  Open source  ·  Runs entirely on your Mac", font=small, fill=MUTED)
draw.text((96, 512), "justscribe.quassum.com", font=small, fill=MUTED)

card.convert("RGB").save(WEB / "public/og.png", optimize=True)
print("wrote", WEB / "public/og.png", card.size)
```

```bash
cd web && OG_FONTS=../../neural-sheet/app/NeuralSheet/Resources/Fonts python3 scripts/og-image.py; cd ..
```

Expected: `wrote …/public/og.png (1200, 630)`. Open it and check the icon is not clipped; if the macOS icon export has a wide transparent margin, change the crop box to `(0, 0, 1024, 1024)`.

- [ ] **Step 5: Layout, download control, styles, 404**

```bash
NSW=/Users/antoni/Projects/neural-sheet/web
cp $NSW/src/layouts/Base.astro web/src/layouts/
cp $NSW/src/components/Download.astro web/src/components/
cp $NSW/src/styles/global.css web/src/styles/
cp $NSW/src/pages/404.astro web/src/pages/
cd web
sed -i '' -e 's/NeuralSheet: audio-to-MIDI transcription as a native macOS app/JustScribe: on-device voice dictation for Mac/g' \
  -e 's/NeuralSheet/JustScribe/g' -e 's#bring-shrubbery/neural-sheet#bring-shrubbery/justscribe#g' \
  -e 's/#131417/#0f1217/g' \
  src/layouts/Base.astro src/components/Download.astro src/pages/404.astro src/styles/global.css
sed -i '' 's/macOS 26, Apple silicon/macOS 26.2, Apple silicon/' src/components/Download.astro
cd ..
```

In `web/src/styles/global.css`:
- First line comment: `/* JustScribe website: one column; the accent is the blue of the app icon. */`
- In `:root` set `--bg: #0f1217; --bg-panel: #141820; --bg-control: #1a1f29; --line: #232937; --line-soft: #1e2430; --accent: #3d9bff; --accent-text: #8cc4ff; --accent-fill: rgba(61, 155, 255, 0.12); --accent-fill-hover: rgba(61, 155, 255, 0.2);` (other tokens unchanged).
- In the light block set `--accent: #0a72e0; --accent-text: #0a5fbd; --accent-fill: rgba(10, 114, 224, 0.08); --accent-fill-hover: rgba(10, 114, 224, 0.14);`.
- Delete the `/* Shortcuts line */` rules (two lines); nothing uses them.

- [ ] **Step 6: Write `web/src/pages/index.astro`**

```astro
---
import Base from '../layouts/Base.astro';
import Download from '../components/Download.astro';
import { Image } from 'astro:assets';
import icon from '../assets/icon.png';
import screenshot from '../assets/screenshot.png';
import { fetchLatestRelease } from '../lib/release';

// Workers Builds share egress addresses; an optional token lifts the per-address limit.
const release = await fetchLatestRelease(fetch, import.meta.env.GITHUB_TOKEN);
const repo = 'https://github.com/bring-shrubbery/justscribe';
const site = 'https://justscribe.quassum.com';
const title = 'JustScribe: Free On-Device Voice Dictation for Mac';
const description =
  'Free, open-source voice dictation for Mac. Hold a shortcut, speak, and the text is typed into whatever app you are in. Transcription runs entirely on your Mac.';

// The FAQ, rendered as a section and as FAQPage structured data. Plain text only:
// answer engines quote it, so every sentence must hold without the page around it.
const faq: { q: string; a: string }[] = [
  {
    q: 'Is JustScribe free?',
    a: 'Yes. JustScribe is free and open source under the GNU General Public License v3.0. There are no subscriptions, accounts or usage limits.',
  },
  {
    q: 'Does it work offline?',
    a: 'Yes. Transcription and grammar correction run on your Mac; your audio never leaves it. The only network use is downloading a model the first time you pick it, and checking for updates.',
  },
  {
    q: 'Which Macs does it run on?',
    a: 'macOS 26.2 or later on Apple silicon (M1 and newer). There is no Intel build.',
  },
  {
    q: 'Why does it need Accessibility permission?',
    a: 'JustScribe types the transcribed text into the app you are using by sending keystrokes, which macOS only allows for apps you have granted Accessibility access. Microphone access is needed to hear you.',
  },
  {
    q: 'Which languages does it understand?',
    a: 'The recommended Parakeet v3 model and the Whisper models are multilingual. Parakeet English is English only and slightly smaller.',
  },
  {
    q: 'I installed JustScribe from the Mac App Store. How do I move to this version?',
    a: 'Download JustScribe here and drag it into Applications, replacing the App Store copy. Your downloaded models and settings are kept. macOS will ask for Accessibility permission again because the app is signed differently; if the switch has no effect, remove the old JustScribe entry in System Settings, Privacy & Security, Accessibility and add it again. From then on the app updates itself.',
  },
  {
    q: 'How do updates work?',
    a: 'JustScribe checks for a new version once a day and installs it in the background the next time the app quits. You can turn that off or check by hand in Settings, Updates.',
  },
];

const structuredData = {
  '@context': 'https://schema.org',
  '@graph': [
    {
      '@type': 'Organization',
      '@id': 'https://quassum.com/#organization',
      name: 'Quassum',
      url: 'https://quassum.com',
    },
    {
      '@type': 'WebSite',
      '@id': `${site}/#website`,
      url: `${site}/`,
      name: 'JustScribe',
      publisher: { '@id': 'https://quassum.com/#organization' },
    },
    {
      '@type': 'SoftwareApplication',
      '@id': `${site}/#app`,
      name: 'JustScribe',
      url: `${site}/`,
      description,
      applicationCategory: 'ProductivityApplication',
      applicationSubCategory: 'Voice dictation',
      operatingSystem: 'macOS 26.2 or later (Apple silicon)',
      image: `${site}/icon.png`,
      screenshot: new URL(screenshot.src, Astro.site).href,
      license: 'https://www.gnu.org/licenses/gpl-3.0.html',
      isAccessibleForFree: true,
      offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
      author: { '@id': 'https://quassum.com/#organization' },
      publisher: { '@id': 'https://quassum.com/#organization' },
      sameAs: [repo],
      featureList: [
        'Dictate into any app with a global hold-to-record shortcut',
        'Live transcription while you speak, with a final accuracy pass on release',
        'On-device transcription with Parakeet and Whisper models',
        'Optional on-device grammar, spelling and punctuation correction',
        'Customizable shortcut, including modifier-only shortcuts',
        'Automatic updates',
      ],
      ...(release
        ? {
            softwareVersion: release.version.replace(/^v/, ''),
            downloadUrl: release.dmgURL,
            releaseNotes: release.notesURL,
          }
        : { downloadUrl: `${repo}/releases/latest` }),
    },
    {
      '@type': 'FAQPage',
      '@id': `${site}/#faq`,
      mainEntity: faq.map(({ q, a }) => ({
        '@type': 'Question',
        name: q,
        acceptedAnswer: { '@type': 'Answer', text: a },
      })),
    },
  ],
};
---
<Base title={title} description={description} structuredData={structuredData}>
  <main>
    <a class="github" href={repo} aria-label="JustScribe on GitHub">
      <svg viewBox="0 0 16 16" aria-hidden="true" fill="currentColor">
        <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
      </svg>
    </a>
    <section class="hero">
      <Image class="icon" src={icon} width={96} height={96} densities={[1, 2]} alt="" loading="eager" />
      <h1>JustScribe <span class="subtitle">Voice dictation for Mac, entirely on-device</span></h1>
      <p class="lead">
        Hold a shortcut, speak, and the text is typed into whatever app you are in. No account, no
        subscription, and your voice never leaves your Mac.
      </p>
      <Download release={release} />
      <Image
        class="screenshot"
        src={screenshot}
        widths={[680, 1360]}
        sizes="(max-width: 712px) 100vw, 680px"
        alt="JustScribe's recording indicator dropping from the MacBook notch: a red microphone and the words Listening, speak now"
        loading="eager"
        fetchpriority="high"
      />
    </section>

    <section id="what">
      <h2>What it does</h2>
      <ul>
        <li><strong>Dictate anywhere.</strong> A global shortcut works in every app: editors, browsers, chat, the terminal. The text goes where your cursor is.</li>
        <li><strong>Hold to record.</strong> Text appears while you speak. When you let go, JustScribe transcribes the whole recording once more for accuracy.</li>
        <li><strong>Stay on your Mac.</strong> Transcription runs on-device with Parakeet or Whisper models. Nothing is uploaded.</li>
        <li><strong>Fix the grammar, if you like.</strong> Optional on-device correction of grammar, spelling and punctuation, using Apple Intelligence or a local Llama model.</li>
        <li><strong>Make it yours.</strong> Any shortcut, including modifier-only ones; microphone priority order; a floating bubble or a notch indicator; light and dark appearance.</li>
        <li><strong>Stay out of the way.</strong> Lives in the menu bar, can launch at login, can copy each transcription to the clipboard, and updates itself.</li>
      </ul>
    </section>

    <section id="start">
      <h2>Quick start</h2>
      <ol>
        <li><strong>Install.</strong> Open the disk image and drag JustScribe into Applications.</li>
        <li><strong>Pick a model.</strong> On first launch, download a transcription model. Parakeet v3 is the recommended one.</li>
        <li><strong>Grant two permissions.</strong> Microphone, to hear you, and Accessibility, to type into other apps.</li>
        <li><strong>Dictate.</strong> Put the cursor in any text field, hold <kbd>Control</kbd> <kbd>Shift</kbd> <kbd>Space</kbd>, speak, and release.</li>
      </ol>
      <p class="muted">The shortcut, model, microphone order and behaviour are all in Settings.</p>
    </section>

    <section id="models">
      <h2>Models</h2>
      <p>Models are downloaded on demand and stored on your Mac. Pick one in Settings; you can switch at any time.</p>
      <div class="table-scroll">
        <table>
          <thead>
            <tr><th scope="col">Model</th><th scope="col">Download</th><th scope="col">Languages</th><th scope="col">Notes</th></tr>
          </thead>
          <tbody>
            <tr><td>Parakeet v3</td><td class="num">~250 MB</td><td>Multilingual</td><td>Recommended</td></tr>
            <tr><td>Parakeet English</td><td class="num">~200 MB</td><td>English</td><td></td></tr>
            <tr><td>Whisper Tiny</td><td class="num">~75 MB</td><td>Multilingual</td><td>Smallest</td></tr>
            <tr><td>Whisper Base</td><td class="num">~142 MB</td><td>Multilingual</td><td></td></tr>
            <tr><td>Whisper Small</td><td class="num">~466 MB</td><td>Multilingual</td><td></td></tr>
            <tr><td>Whisper Medium</td><td class="num">~1.5 GB</td><td>Multilingual</td><td></td></tr>
            <tr><td>Whisper Large v3</td><td class="num">~3 GB</td><td>Multilingual</td><td>Largest</td></tr>
          </tbody>
        </table>
      </div>
      <p class="muted">
        Grammar correction is off by default. It can use the model built into macOS when Apple Intelligence is
        enabled (no download), or Llama 3.1 8B (~4.6 GB download, about 5 GB of memory while loaded).
      </p>
    </section>

    <section id="app-store">
      <h2>Coming from the App Store version</h2>
      <p>
        JustScribe is no longer distributed through the Mac App Store. Download it here and drag it into
        Applications, replacing the old copy. Your models and settings are kept.
      </p>
      <div class="callout">
        <p>
          <strong>macOS will ask for Accessibility permission again</strong>, because this version is signed
          differently. If the switch has no effect, remove the old JustScribe entry in System Settings →
          Privacy &amp; Security → Accessibility and add it again.
        </p>
      </div>
    </section>

    <section id="faq">
      <h2>Questions</h2>
      <dl class="faq">
        {faq.map(({ q, a }) => (
          <div>
            <dt>{q}</dt>
            <dd>{a}</dd>
          </div>
        ))}
      </dl>
    </section>

    <section id="source">
      <h2>Source and license</h2>
      <p>
        JustScribe is open source under the <a href={`${repo}/blob/main/LICENSE`}>GNU General Public License v3.0</a>.
        The code is on <a href={repo}>GitHub</a>; bug reports and feature requests go to
        <a href={`${repo}/issues`}>Issues</a>. To build it yourself, clone the repository, open
        <code>app/justscribe.xcodeproj</code> in Xcode and run the <strong>justscribe</strong> scheme.
      </p>
      <p class="muted">
        <a href="https://quassum.com/apps/justscribe/privacy">Privacy policy</a> ·
        <a href="https://quassum.com/terms">Terms</a> ·
        <a href="https://github.com/sponsors/bring-shrubbery">Sponsor the project</a>
      </p>
    </section>
  </main>
  <footer>
    <div class="inner">
      <span>JustScribe</span>
      <a href={repo}>GitHub</a>
      <a href={`${repo}/releases`}>Releases</a>
      <a href="https://quassum.com/apps/justscribe/privacy">Privacy</a>
      <a href="https://quassum.com">Quassum</a>
    </div>
  </footer>
</Base>
```

In `web/src/pages/404.astro` the sed already renamed everything; confirm the sentence reads "JustScribe is a single page".

- [ ] **Step 7: `web/public/llms.txt` and `web/README.md`**

`web/public/llms.txt`:

```markdown
# JustScribe

> Voice dictation as a native macOS menu-bar app. Hold a global shortcut, speak, and the transcribed text is typed into whatever app has focus. Transcription and grammar correction run entirely on the Mac; nothing is uploaded.

JustScribe is a free, open-source (GPL-3.0) app by Quassum for macOS 26.2 and later on Apple silicon.

## Key facts

- Platform: macOS 26.2 or later, Apple silicon only. Signed and notarized disk image; no longer on the Mac App Store.
- Price: free. No account, subscription or usage limit.
- How it works: hold the shortcut (default Control + Shift + Space) to record; text streams in while speaking and is re-transcribed for accuracy on release.
- Transcription models: Parakeet v3 (recommended, multilingual, ~250 MB), Parakeet English (~200 MB), Whisper Tiny, Base, Small, Medium and Large v3 (75 MB to 3 GB). Downloaded on demand.
- Grammar correction: optional, on-device, through Apple Intelligence or Llama 3.1 8B (~4.6 GB).
- Permissions: Microphone, and Accessibility to type into other apps.
- Updates: the app updates itself; releases are published on GitHub.

## Links

- [Website](https://justscribe.quassum.com/): download and overview
- [Latest release](https://github.com/bring-shrubbery/justscribe/releases/latest): the .dmg and release notes
- [Source code](https://github.com/bring-shrubbery/justscribe): GitHub repository and README
- [Issues](https://github.com/bring-shrubbery/justscribe/issues): bug reports and feature requests
- [Privacy policy](https://quassum.com/apps/justscribe/privacy)
- [Quassum](https://quassum.com/): the studio behind JustScribe, Vilnius, Lithuania
```

`web/README.md`:

```bash
cp /Users/antoni/Projects/neural-sheet/web/README.md web/README.md
sed -i '' -e 's/NeuralSheet/JustScribe/g' -e 's#bring-shrubbery/neural-sheet#bring-shrubbery/justscribe#g' \
  -e 's#neural-sheet\.quassum\.com#justscribe.quassum.com#g' -e 's/neural-sheet-web/justscribe-web/g' web/README.md
```

Then, in step 1 of "Deploy", replace "or Cloudflare's autofix opens a pull request that the PR gate closes" with "or Cloudflare's autofix opens a pull request to rename it".

- [ ] **Step 8: Check, test, build, and look at it**

```bash
cd web
grep -rn -i "neural" --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.astro --exclude=package-lock.json . | grep -v "fonts/README.md\|og-image.py"   # must print nothing
npm run check 2>&1 | tail -4
npm test 2>&1 | tail -5
npm run build 2>&1 | tail -6
grep -o 'Download JustScribe[^<]*' dist/index.html | head -1
grep -c "releases/latest" dist/index.html
npx wrangler deploy --dry-run 2>&1 | tail -5
npm run preview &
sleep 3
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4321/
kill %1
cd ..
```

Expected: no `neural` hits; `0 errors`; tests pass; build completes with `/index.html` and `/404.html`; the button reads `Download JustScribe` (no release exists yet, so the fallback — and at least one `releases/latest` link); the dry run lists the assets without error; `200`.

Open `http://localhost:4321/` during `npm run preview` in a browser at desktop width and at 390 px: one column, no horizontal scroll, the table scrolls inside its own box, the screenshot has a border radius, light and dark both legible.

- [ ] **Step 9: Commit**

```bash
git add web
git status --short | grep -E "node_modules|dist/" && echo "STOP: build output staged"
git commit -m "web: the JustScribe website"
```

---

### Task 8: Handoff — secrets, Cloudflare, first release

Nothing here is code. Each step needs the maintainer's credentials or explicit go-ahead; do not push, merge, set secrets or touch Cloudflare without it.

- [ ] **Step 1: Whole-branch verification**

```bash
for t in app/Scripts/release-*-test.sh; do "$t" | tail -1; done
actionlint
xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -destination 'platform=macOS' test -only-testing:justscribeTests 2>&1 | tail -3
(cd web && npm run check && npm test && npm run build) 2>&1 | tail -6
git status --short
```

Expected: four `all passed`; actionlint silent; `** TEST SUCCEEDED **`; web green; clean tree.

- [ ] **Step 2: Update the project memory**

In `/Users/antoni/.claude/projects/-Users-antoni-Projects-justscribe/memory/MEMORY.md`: the build command becomes `xcodebuild -project app/justscribe.xcodeproj -scheme justscribe -configuration Debug build`; file references gain `app/justscribe/`. Add a `project` memory `releases-ship-from-main.md`: every code commit on `main` is released to users automatically since the direct-distribution work, so work on a branch and treat commit subjects as release notes; link it from `MEMORY.md`.

- [ ] **Step 3: Repository secrets (maintainer)**

Follow `docs/release.md` → "One-time setup". The Sparkle private key export uses `generate_keys` from Task 4 Step 1 (`$T` is that step's temporary directory; if it is gone, repeat that step's download, checksum and `tar` lines — not the `generate_keys --account JustScribe` line's result, which is already in the keychain):

```bash
"$T/bin/generate_keys" --account JustScribe -x sparkle-justscribe.key
gh secret set SPARKLE_PRIVATE_KEY < sparkle-justscribe.key
# copy sparkle-justscribe.key to an off-machine backup, then:
rm sparkle-justscribe.key
gh secret list
```

Expected: eight names (`MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY`, `APPLE_TEAM_ID`, `ASC_API_KEY_P8`, `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`, `SPARKLE_PRIVATE_KEY`).

- [ ] **Step 4: Merge and watch the first release (maintainer go-ahead required)**

Push the branch, open a pull request, let CI run on it (this is where the hosted runner's macOS version and Metal toolchain are first exercised — fix forward on the branch), merge. The merge to `main` triggers CI, then Release → `v1.3.0`.

```bash
gh run watch
gh release view v1.3.0 --json assets --jq '.assets[].name'
```

Expected: `JustScribe-v1.3.0-macos-arm64.dmg`, `JustScribe-v1.3.0-macos-arm64.zip`, `appcast.xml`.

- [ ] **Step 5: Cloudflare (maintainer)**

Follow `web/README.md` → "Deploy": import the repository as Worker `justscribe-web`, root `web`, custom domain `justscribe.quassum.com`, deploy hook → `gh secret set CF_DEPLOY_HOOK_URL`. Then:

```bash
curl -sI https://justscribe.quassum.com/appcast.xml | grep -i -E "^HTTP|^location"
curl -s https://justscribe.quassum.com/ | grep -o 'Download JustScribe v[0-9.]*' | head -1
```

Expected: `302` to `github.com/bring-shrubbery/justscribe/releases/latest/download/appcast.xml`; `Download JustScribe v1.3.0`.

- [ ] **Step 6: End-to-end update (maintainer)**

Install v1.3.0 from the DMG over the App Store copy; confirm models and settings survived and re-grant Accessibility. Land any small code change on `main` → v1.3.1. In the installed v1.3.0 choose "Check for Updates…": it must offer v1.3.1 with the commit subject as notes, install, and relaunch as 1.3.1. Only then follow "Leaving the App Store" in `docs/release.md`.
