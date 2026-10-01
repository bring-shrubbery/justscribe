# Direct distribution: website, automatic releases, in-app updates — design

JustScribe leaves the Mac App Store. Every code change that lands on `main` and
passes CI becomes a Developer ID signed, notarized
`JustScribe-vX.Y.Z-macos-arm64.dmg` on a GitHub release; a one-page site at
`https://justscribe.quassum.com` offers it for download; installed copies update
themselves through Sparkle. The pipeline is neural-sheet's
(`../neural-sheet`: `.github/workflows/`, `app/Scripts/`, `web/`,
`docs/release.md`), adapted where JustScribe differs.

## Decisions

| Question | Decision |
|---|---|
| App Store version | Replaced. Direct download is the only channel; one build variant. |
| Sandbox | Kept. Same bundle ID (`com.quassum.justscribe`) and container, so models and settings survive the move with no migration code. |
| Tip jar | StoreKit removed; a "Support JustScribe" row opens GitHub Sponsors. |
| Website | New site in `web/`, served at `justscribe.quassum.com`. |
| Release trigger | Every green CI run of a push to `main` that changes code. |

## 1. Repository layout

```
app/
  justscribe.xcodeproj
  justscribe/            (sources, Info.plist, entitlements)
  justscribeTests/
  justscribeUITests/
  Scripts/               (release-*.sh and their -test.sh)
web/                     (Astro site)
docs/                    (superpowers/specs, superpowers/plans, release.md)
icon-composer/  screenshots/
README.md  CLAUDE.md  LICENSE  .gitignore
.github/workflows/ci.yml  release.yml
.github/FUNDING.yml
```

- `justscribe.xcodeproj`, `justscribe/`, `justscribeTests/` and
  `justscribeUITests/` move into `app/` with `git mv`, in one commit that
  changes nothing else. The project's file-system-synchronized groups and its
  `INFOPLIST_FILE` / `CODE_SIGN_ENTITLEMENTS` settings are relative to the
  project, so `project.pbxproj` is untouched by the move.
- `Products.storekit` is deleted (section 2), not moved.
- A root `.gitignore` is added (the repository has none): `xcuserdata/`,
  `*.xcuserstate`, `DerivedData/`, `build/`, `.build/`, `.swiftpm/`,
  `.DS_Store`, `.superpowers/`, `web/node_modules/`, `web/dist/`, `web/.astro/`,
  `web/.wrangler/`. The tracked
  `xcuserdata/antoni.xcuserdatad/xcschemes/xcschememanagement.plist` is removed
  from the index.
- `CLAUDE.md`: commands gain `-project app/justscribe.xcodeproj`, paths gain
  `app/`, the StoreKit gotcha is replaced by a short release/update paragraph
  pointing at `docs/release.md`. `README.md`: the icon path, the "Open in
  Xcode" steps, and the download link (to `https://justscribe.quassum.com`).

## 2. App changes

### Sparkle

- Sparkle 2 (2.10.0, up to next major) added to the `justscribe` target as a
  Swift package. The `project.pbxproj` edit (package reference, product
  dependency, framework build file) is made by hand and proven by a Debug build
  and the unit tests; `Package.resolved` is committed.
- `app/justscribe/Info.plist` (exists, empty, already named by `INFOPLIST_FILE`
  and merged with the generated plist) gains:
  - `SUFeedURL` = `https://justscribe.quassum.com/appcast.xml`
  - `SUPublicEDKey` = the public half of a new key pair
    (`generate_keys --account JustScribe`, section 5)
  - `SUEnableAutomaticChecks` = true (no first-run permission prompt)
  - `SUAutomaticallyUpdate` = true (download and install without asking; the
    user can turn it off)
  - `SUEnableInstallerLauncherService` = true (required in a sandbox)
- `app/justscribe/justscribe.entitlements` gains
  `com.apple.security.temporary-exception.mach-lookup.global-name` with
  `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`.
  The downloader XPC service stays disabled: the app already holds
  `com.apple.security.network.client`.
- `app/justscribe/Services/UpdateService.swift`: a
  `@MainActor @Observable final class UpdateService` singleton, in the style of
  the other services. It owns one
  `SPUStandardUpdaterController(startingUpdater: true, …)` for the app's
  lifetime and exposes:
  - `canCheckForUpdates: Bool` (mirrors the updater's KVO property)
  - `automaticallyInstallsUpdates: Bool` (reads and writes
    `updater.automaticallyDownloadsUpdates`; Sparkle persists it itself, so it
    does not go through `AppSettings`' dual-write)
  - `checkForUpdates()`
  `AppDelegate` touches `UpdateService.shared` at launch so scheduled checks
  start.
- UI:
  - Status-item menu (`AppDelegate`, between "Settings..." and "Quit"):
    "Check for Updates…", disabled while `canCheckForUpdates` is false.
  - Settings: an "Updates" section
    (`Views/Settings/Sections/UpdateSettingsSection.swift`) with the current
    version, an "Automatically install updates" toggle and a "Check Now"
    button.
- Behaviour: Sparkle checks on launch and every 24 hours. With automatic
  updates on, a new version is downloaded silently and installed when the app
  quits; an app that never quits gets Sparkle's own prompt after its grace
  period. With the toggle off, Sparkle shows its standard dialog with the
  release notes.

### Tip jar

- Deleted: `Services/TipJarService.swift`,
  `Views/Settings/Sections/TipJarSettingsSection.swift`, `Products.storekit`,
  the scheme's `StoreKitConfigurationFileReference`, and every reference to
  them.
- Added: `Views/Settings/Sections/SupportSettingsSection.swift`, in the tip
  jar's place — one row, "Support JustScribe", with a short line of text and a
  button opening `https://github.com/sponsors/bring-shrubbery`. The URL lives
  with the other links in `Utilities/Constants.swift`.
- `.github/FUNDING.yml`: `github: bring-shrubbery`.

### Version

- `MARKETING_VERSION` = `1.3.0` (the App Store build is 1.2). Release builds
  get `CURRENT_PROJECT_VERSION` = the workflow run number + 100, so the build
  number is monotonic (what Sparkle compares) and above the App Store's build 8.

## 3. CI and release

### `.github/workflows/ci.yml`

On push and pull request to `main`; concurrency per ref, cancel in progress.

- **app** (`macos-26`, newest installed Xcode): Debug build, unsigned
  (`CODE_SIGNING_ALLOWED=NO`), then
  `xcodebuild test -only-testing:justscribeTests` (the UI tests need a session
  and permissions and are not run). The tests need the runner's macOS to be at
  least the deployment target (26.2); if it is not, the job is build-only and
  the test step is restored when the image catches up — decided on the first
  run, recorded in `docs/release.md`.
- **scripts** (`ubuntu-latest`): runs each `app/Scripts/release-*-test.sh`.
- **web** (`ubuntu-latest`): `npm ci`, `npm run check`, `npm test`,
  `npm run build` in `web/`.

### Scripts (`app/Scripts/`, copied from neural-sheet and renamed)

- `release-version.sh` — `max(MARKETING_VERSION in
  app/justscribe.xcodeproj/project.pbxproj, highest strict vX.Y.Z tag with
  patch + 1)`; `--previous` prints the last release tag. Every configuration
  must carry the same three-component version, so all six (the test targets
  too) are set to `1.3.0`.
- `release-changes.sh` — paths changed since the previous tag, ignoring
  `docs/`, `web/`, `icon-composer/`, `screenshots/`, `*.md`, `LICENSE`,
  `.gitignore` and `.github/` except `.github/workflows/`. Empty output means
  no release.
- `release-notes.sh` — commit subjects since the previous tag, oldest first,
  as HTML (the appcast) or Markdown (the release body). This repository's
  subjects are plain sentences without an `area:` prefix, so they are used as
  written. Commits whose subject starts with `docs:`, `web:` or `ci:` are left
  out, as are merge commits; nothing else is filtered.
- `release-appcast.sh` — writes the one-item feed from its arguments;
  `sparkle:minimumSystemVersion` = `26.2`.
- Each has a `-test.sh` beside it, adapted with the script.
- `release-resign.sh <app> <identity>` — new: the inside-out re-signing of
  Sparkle's helpers and the app described in the workflow below, with its
  assertions, as a script so it can be rehearsed locally with the Developer ID
  certificate before the first release.

### `.github/workflows/release.yml`

neural-sheet's workflow with the engine cache and submodules removed and names
changed. `workflow_run` of CI on `main` (success, push) or `workflow_dispatch`
on `main`; concurrency group `release`, no cancel.

1. **Decide the version** (`ubuntu-latest`): previous tag, changed paths,
   version, tag, sha.
2. **Build and publish** (`macos-26`):
   1. Fail at once, naming them, if any of the eight secrets is missing.
   2. Import the Developer ID certificate into a throwaway keychain.
   3. `xcodebuild archive`, Release, arm64, `CODE_SIGN_STYLE=Manual`, the
      Developer ID identity, `MARKETING_VERSION=$VERSION`,
      `CURRENT_PROJECT_VERSION=$((GITHUB_RUN_NUMBER + 100))`.
   4. Re-sign Sparkle inside out with the hardened runtime and a timestamp:
      `Installer.xpc`, `Downloader.xpc` (preserving its entitlements),
      `Autoupdate`, `Updater.app`, `Sparkle.framework`, then the app. The app's
      entitlements are **extracted from the archived app**
      (`codesign -d --entitlements - --xml`), not read from the source file,
      which contains the unresolved `$(PRODUCT_BUNDLE_IDENTIFIER)`. Assert each
      helper is Developer ID signed, that the re-signed app still carries
      `com.apple.security.app-sandbox` and both mach-lookup names, and that
      `codesign --verify --deep --strict` passes and the built version matches.
   5. `create-dmg` → `JustScribe-$TAG-macos-arm64.dmg` (volume name
      `JustScribe $TAG`, app + Applications link), with the same
      retry-without-Finder-layout fallback.
   6. Sign the DMG, `notarytool submit --wait` with the App Store Connect API
      key, print Apple's log on anything but `Accepted`, staple DMG and app,
      `spctl --assess`, `ditto` the app into
      `JustScribe-$TAG-macos-arm64.zip`.
   7. Download Sparkle's tools pinned by version and SHA-256, `sign_update` the
      zip, write release notes (HTML and Markdown) and `appcast.xml`,
      `xmllint --noout`.
   8. Upload DMG, zip and appcast as run artifacts; delete the keychain.
   9. Tag `vX.Y.Z` on the built commit (fails if the tag exists), publish the
      GitHub release `JustScribe vX.Y.Z` with the three assets.
   10. `POST` `CF_DEPLOY_HOOK_URL` to rebuild the site (warning, not failure,
       when the secret is empty).

The app bundle stays `justscribe.app` (`PRODUCT_NAME` is unchanged, so
existing installs, login items and permissions keep their path); only the
release asset names and display strings say "JustScribe".

## 4. Website (`web/`)

- neural-sheet's setup, copied: Astro 7 static output, TypeScript strict, npm
  lockfile, `.nvmrc`, one global stylesheet, Vitest, `wrangler.jsonc` with
  `name: "justscribe-web"`, `workers_dev: false`,
  `assets: { directory: "./dist", not_found_handling: "404-page" }`, the same
  `_headers`, `robots.txt`, sitemap, `llms.txt`, 404 page.
- `public/_redirects`:
  ```
  /appcast.xml  https://github.com/bring-shrubbery/justscribe/releases/latest/download/appcast.xml  302
  /download     https://github.com/bring-shrubbery/justscribe/releases/latest  302
  ```
- `src/lib/release.ts` (+ test): the latest GitHub release at build time →
  `Release | null`; the button reads "Download JustScribe vX.Y.Z" with the
  caption "macOS 26.2, Apple silicon · N MB · Release notes", or falls back to
  a link to the Releases page. The build never fails because of the API.
- One page, one column, sections condensed from the README:
  1. Hero: icon, "JustScribe", the one-line pitch, the download control, a
     screenshot.
  2. Features.
  3. Quick start (install, pick a model, grant Microphone and Accessibility,
     hold the shortcut).
  4. Models (transcription and grammar correction) and "everything runs
     on-device".
  5. Coming from the App Store version: install the download over it, your
     models and settings are kept, macOS asks for Accessibility again.
  6. Source, license (GPL-3.0), privacy policy and terms (links to
     quassum.com).
- Look: neural-sheet's layout, spacing and type scale (Inter self-hosted,
  JetBrains Mono for code), dark by default with a light theme via
  `prefers-color-scheme`, colours as CSS custom properties with the accent
  taken from the JustScribe icon. Icon, favicon, apple-touch-icon and Open
  Graph image are derived from `icon-composer/` exports and committed; the
  screenshot comes from `screenshots/`.
- `web/README.md`: local development, the Workers Builds dashboard settings
  (root `web`, build `npm run build`, deploy `npx wrangler deploy`, production
  branch `main`, custom domain `justscribe.quassum.com`, non-production builds
  off), the deploy hook, and an optional `GITHUB_TOKEN` build variable for the
  release API.

## 5. Maintainer steps (documented in `docs/release.md`)

These need credentials and cannot be done from the repository:

1. Repository secrets: `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`,
   `MACOS_SIGNING_IDENTITY`, `APPLE_TEAM_ID`, `ASC_API_KEY_P8`,
   `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID` — the same Developer ID certificate
   and App Store Connect key neural-sheet uses (team `6WCYZER5LX`).
2. Sparkle key: `generate_keys --account JustScribe`; the printed public key
   goes into `Info.plist` (`SUPublicEDKey`), the `-x` export into the secret
   `SPARKLE_PRIVATE_KEY` and an off-machine backup. Losing both strands every
   installed copy. This is done during implementation, before the Info.plist
   commit; no placeholder key is ever committed.
3. Cloudflare: connect the repository to Workers Builds, add the custom
   domain, create the deploy hook, set `CF_DEPLOY_HOOK_URL`.
4. After the first release works end to end: remove the app from sale in App
   Store Connect, and point `quassum.com/apps/justscribe` at the new site
   (another repository).

`docs/release.md` also carries the versioning rules, the release-notes
convention (commit subjects are what users read), and the "when it fails"
list, adapted from neural-sheet.

## Error handling

- A missing secret, a non-Developer-ID helper, a lost entitlement, a version
  mismatch or a notarization status other than `Accepted` fails the release
  before anything is tagged or published.
- An existing tag fails the run rather than being overwritten; the artifacts
  of the run that tagged are kept for manual publishing.
- The website build and the release never depend on each other: the site falls
  back to the Releases link, and a failed deploy hook leaves a published
  release with a stale button.
- In the app, Sparkle's own dialogs report failed checks and bad signatures;
  `UpdateService` adds no error UI.

## Testing

- Script tests (`release-*-test.sh`) locally and in CI; `actionlint` on both
  workflows.
- `xcodebuild build` and the unit tests after each app step (the move, the
  tip jar removal, Sparkle); the app target must stay green at every commit.
- Web: `npm run check`, `npm test`, `npm run build`; the built page opened at
  desktop and phone width.
- Local signing check before the first release: an archive signed with the
  Developer ID identity and re-signed by the workflow's procedure passes
  `codesign --verify --deep --strict` and keeps the sandbox entitlements.
- End to end, by the maintainer: the first release (v1.3.0) installs from the
  DMG over the App Store copy and keeps models and settings; a second code
  push (v1.3.1) is offered and installed by the first.

## Risks

- Moving from an App Store signature to Developer ID changes the code
  requirement TCC stored, so users re-grant Accessibility (and possibly
  Microphone). The site and the v1.3.0 notes say so.
- Sparkle's sandboxed installer is the least-travelled part: neural-sheet is
  not sandboxed. The local signing check and the v1.3.0 → v1.3.1 update are the
  proof; until the second passes, the App Store listing stays up.
- Every code commit on `main` ships. Work in progress belongs on a branch.

## Out of scope

Delta updates, beta channels, update statistics, analytics, an Intel build,
neural-sheet's contributor-gate workflows and community files, changes to
quassum.com, and any final App Store update announcing the move.
