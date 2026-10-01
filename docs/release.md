# Releasing JustScribe

Releases are automatic. Every push to `main` that passes CI and changes
something other than documentation is built, signed, notarized and published as
`JustScribe-vX.Y.Z-macos-arm64.dmg` (and a zip of the app) on a GitHub
release tagged `vX.Y.Z`. Installed copies update themselves from the
`appcast.xml` each release publishes (Sparkle).

## Versions

The workflow computes the version: the higher of `MARKETING_VERSION` in
`app/justscribe.xcodeproj` and the last release tag with its patch bumped.

- A code push after `v1.3.0` releases `v1.3.1`. Nothing to do.
- To ship a minor or major, set `MARKETING_VERSION` (Xcode → target justscribe →
  General → Version) to, say, `1.4.0` and push; set it on all three targets — the
  release stops if they disagree. That push releases `v1.4.0`; the next one
  `v1.4.1`. CI never edits the project file.
- The build number (`CURRENT_PROJECT_VERSION`) is the workflow run number + 100,
  which keeps it above the last App Store build (8).
- Pushes that change only `docs/`, `web/`, `icon-composer/`, `screenshots/`,
  `*.md`, `LICENSE`, `.gitignore` or `.github/` (except the workflows) release
  nothing. The run says so in its log.

The GitHub release body and the notes the update prompt shows are the commit
subjects since the previous tag (`app/Scripts/release-notes.sh`), as written.
Commits whose subject starts with `docs:`, `web:` or `ci:` are left out, so use
those prefixes for changes users never see, and write every other subject as the
line a user will read.

## One-time setup: the secrets

The Developer ID certificate and the App Store Connect key are the ones
neural-sheet uses (team `6WCYZER5LX`); export or reuse the same files and set
them on this repository.

The workflow refuses to run without all eight of these repository secrets; an
unsigned build must never reach a release.

### 1. The Developer ID certificate

You need the `Developer ID Application: Quassum MB (6WCYZER5LX)` certificate
*with its private key* on the Mac you export from (`security find-identity -v
-p codesigning` lists it).

1. Keychain Access → My Certificates → right-click the certificate → Export.
   Choose `.p12`, set a password, save as `developer-id.p12`.
2. Encode and store it, then delete the file:

```sh
gh secret set MACOS_CERTIFICATE_P12 < <(base64 -i developer-id.p12)
gh secret set MACOS_CERTIFICATE_PASSWORD        # paste the .p12 password
gh secret set MACOS_SIGNING_IDENTITY --body "Developer ID Application: Quassum MB (6WCYZER5LX)"
gh secret set APPLE_TEAM_ID --body 6WCYZER5LX
rm developer-id.p12
```

### 2. The App Store Connect API key (for notarization)

1. https://appstoreconnect.apple.com → Users and Access → Integrations →
   App Store Connect API → Team Keys → **Generate API Key**.
   Name it `JustScribe CI`, access **Developer**.
2. Download the `.p8` (only offered once) and note the **Key ID** on that row
   and the **Issuer ID** above the table.
3. Store them, then delete the file:

```sh
gh secret set ASC_API_KEY_P8 < AuthKey_XXXXXXXXXX.p8
gh secret set ASC_API_KEY_ID --body XXXXXXXXXX
gh secret set ASC_API_ISSUER_ID --body 00000000-0000-0000-0000-000000000000
rm AuthKey_XXXXXXXXXX.p8
```

`gh secret list` should now show seven names; the eighth is the Sparkle key below.

### 3. Sparkle (in-app updates)

Every release also publishes `appcast.xml`, the feed installed copies read through
`https://justscribe.quassum.com/appcast.xml` (a redirect to the latest release's
asset). The zip is signed with an EdDSA key so the app accepts only our builds.

The key pair was generated on 2026-10-01 with Sparkle's
`generate_keys --account JustScribe`. The private key lives in the login keychain
of the Mac that ran it (Keychain Access → search "sparkle-project.org", account
`JustScribe`) and in the repository secret `SPARKLE_PRIVATE_KEY`. **Losing both
means no installed copy can ever update again.** Back it up once:
`generate_keys --account JustScribe -x sparkle-justscribe.key` and keep the file
somewhere safe, off this machine. To set it in the repository:
`gh secret set SPARKLE_PRIVATE_KEY < sparkle-justscribe.key`, then delete the file.
The matching public key is `SUPublicEDKey` in `app/justscribe/Info.plist`.
`gh secret list` should now show all eight names.

The app is sandboxed, so Sparkle installs through its XPC launcher service
(`SUEnableInstallerLauncherService`) and the app carries two mach-lookup
entitlements. `app/Scripts/release-resign.sh` re-signs Sparkle's helpers and
refuses to continue if the app lost its sandbox or those entitlements.

If the key is lost: generate a new pair, put the new public key in `app/justscribe/Info.plist`,
set the new secret, and tell users to download the next release by hand — copies
with the old key will report an improperly signed update on every check and never
update on their own.

To rotate the key: ship one release signed with the old key whose Info.plist
carries the new public key, then switch `SPARKLE_PRIVATE_KEY`; copies that skip
that release are stranded, so avoid rotating.

An optional ninth secret is `CF_DEPLOY_HOOK_URL`, the Cloudflare Workers Builds deploy
hook for the website (see `web/README.md`). Without it the release still publishes, with a
warning, and the website keeps offering the previous version until it is rebuilt.

### 4. The first release

Push a code change to `main`, or run the Release workflow from the Actions tab
with **Run workflow** (only `main` is honoured). The `Decide the version` job
prints the version and the changed paths; `Build and publish` takes about
fifteen minutes, most of it Apple's notarization queue. The release appears at
https://github.com/bring-shrubbery/justscribe/releases.

Until the eight secrets exist, every code push produces one red Release run
that stops at the secrets check; that is expected. Quick successive pushes
queue; GitHub keeps one pending run per queue, so a run marked *cancelled* is
not a failure — the next run covers its commits.

#### Leaving the App Store

v1.3.0 is the first direct release. Install it over the App Store copy and
confirm models and settings are still there (same bundle ID, same sandbox
container). macOS asks for Accessibility again because the signature changed:
remove the old JustScribe entry in System Settings → Privacy & Security →
Accessibility if the toggle has no effect. Only after a later release (v1.3.1)
has installed itself through the update prompt: remove the app from sale in App
Store Connect and point quassum.com/apps/justscribe at the new site.

## CI

The CI workflow (`.github/workflows/ci.yml`) runs the unit tests inside the
sandboxed app, signed ad hoc so it carries its entitlements; no build-only
fallback was needed locally. The app's deployment target is macOS 26.2, so the
hosted `macos-26` runner must be at least that; whether it is is only known after
the first run, and the log's `sw_vers` line (in *Select the newest installed
Xcode*) shows it.

## When it fails

"Re-run" below means re-running the failed run while no newer release exists. A
run re-runs the commit it was started for, so once a later push has released,
re-running an older run is refused (the second bullet below): push a new commit or use
**Run workflow** on `main` instead.

- **missing repository secrets** — the first step names them; add and re-run.
- **does not descend from the last release; refusing to release an older commit** —
  by design. The run was building a commit older than the latest release tag,
  almost always because an old failed run was re-run after a newer push had
  already released. Releasing it would ship an older build under a newer version
  and roll back every installed copy. Nothing was built or tagged. Its changes are
  already on `main`, so push a new commit or use **Run workflow** on `main`; that
  run releases everything since the last tag.
- **notarization ended with status Invalid** — the step prints Apple's log;
  the usual causes are a binary without the hardened runtime or a missing
  timestamp. Both are set by the project and the workflow, so look at what
  changed. A third cause is a Sparkle helper that lost its Developer ID
  signature, or an app that lost its entitlements; `release-resign.sh` stops
  with a message naming which.
- **CI is red on the unit tests but the build is fine** — the hosted runner's
  macOS may be older than the app's deployment target (26.2); the log's
  `sw_vers` line shows it.
- **create-dmg could not apply the window layout** — a warning only; the
  image is valid, it just lacks the icon arrangement.
- **Sign the update and write the appcast failed** — the zip is notarized but not
  yet released. Usually `SPARKLE_PRIVATE_KEY` is missing or not the exported key
  (44 base64 characters). Fix the secret and re-run; nothing was tagged.
- **The tag exists** — a previous run tagged but failed to publish. The notarized
  DMG and zip are attached to that run as artifacts (the run page, *Artifacts*).
  Publish all three — the DMG, the zip **and `appcast.xml`** — or installed copies
  will find no feed until the next release. Either publish them by hand as
  release `vX.Y.Z`, or delete the tag
  (`git push origin :refs/tags/vX.Y.Z`) and the release if one was created,
  then re-run. Re-running without deleting the tag prints "no code changes
  since vX.Y.Z" and releases nothing.
- **Rebuild the website failed** — the release is already published; only the site's
  download button is stale. Re-run the build from the Worker's *Builds* page in the
  Cloudflare dashboard (re-running the Release workflow releases nothing: it prints
  "no code changes", or refuses once a newer release exists).
