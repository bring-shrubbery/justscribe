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
  which keeps it above the last App Store build (8). GitHub counts run numbers per
  workflow file, so never rename or recreate `.github/workflows/release.yml`: the
  count would restart, Sparkle would see every new build as older, and installed
  copies would silently stop updating. If it must happen, first raise the offset
  (the `BUILD=` line and the *Summary* step) above the last released build number.
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

`app/Scripts/release-secrets.sh` sets them for you: it asks for the `.p12` and
its password, the `.p8` with its Key ID and Issuer ID, exports the Sparkle key
from the login keychain, checks each value (a trial import of the certificate,
a call to Apple's notary service, the Sparkle key against `SUPublicEDKey`) and
sends it with `gh secret set`. Secrets that already exist are left alone unless
you pass `--all`. The sections below say where each value comes from, and how
to set one by hand.

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
The matching public key is `SUPublicEDKey` in `app/justscribe/Info.plist`:
`generate_keys --account JustScribe -p` must print exactly that value, and the
secret must be that same account's `-x` export (a 44-character base64 seed). The
workflow derives the public key from the secret
(`app/Scripts/release-sparkle-public-key.swift`) and refuses to sign the update
when it differs from the built app's `SUPublicEDKey`; a mismatched key would
publish an update every installed copy rejects.
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

Merging this work into `main` publishes v1.3.0, so first, before merging:

1. **Push a baseline tag** on the commit the last App Store build (1.2, build 8)
   shipped from, so v1.3.0's notes are this work rather than the whole history:

   ```sh
   git tag -a v1.2.0 -m "JustScribe v1.2.0 (last App Store release)" 94f5245
   git push origin v1.2.0
   ```

   `94f5245` is `main`'s tip before direct distribution; use the actual App Store
   commit if it differs. The version is still 1.3.0 (the project's
   `MARKETING_VERSION` is above 1.2.1); only the notes change, listing just the
   commits since the tag.
2. **Check the updater by hand.** Run the app from Xcode once and choose
   **Check for Updates…**: until the first release exists, expect Sparkle's
   update error (the feed has nothing yet), not a crash or silence. Check that
   Settings → Updates shows its controls.

Then push a code change to `main`, or run the Release workflow from the Actions
tab with **Run workflow** (only `main` is honoured; it releases `main`'s tip
without waiting for CI). The `Decide the version` job prints the version and the
changed paths; `Build and publish` takes about fifteen minutes, most of it
Apple's notarization queue. The release appears at
https://github.com/bring-shrubbery/justscribe/releases.

After v1.3.0 is published, edit its release body on GitHub: lead with the
Accessibility notice (macOS asks for Accessibility permission again, because the
app's signature changed; see below) and prune subjects that only make sense
internally. Later releases need no hand edits if their subjects follow the
prefixes above.

Until the eight secrets exist, every code push produces one red Release run
that stops at the secrets check; that is expected. Quick successive pushes
queue; GitHub keeps one pending run per queue, so a run marked *cancelled* is
not a failure: a later run releases its commits too. If no later push follows,
use **Run workflow**.

#### Leaving the App Store

v1.3.0 is the first direct release. Install it over the App Store copy and
confirm models and settings are still there (same bundle ID, same sandbox
container). macOS asks for Accessibility again because the signature changed:
remove the old JustScribe entry in System Settings → Privacy & Security →
Accessibility if the toggle has no effect.

Before removing the App Store listing, check both update paths end to end once
v1.3.1 exists:

- **Check for Updates…** in v1.3.0 offers v1.3.1 and installs it.
- The default path, which every user takes: on another v1.3.0 install, leave
  Settings → Updates → *Automatically install updates* on and let it run until
  it has downloaded v1.3.1 in the background (or trigger a check), quit it,
  relaunch, and confirm it is 1.3.1.

Only then remove the app from sale in App Store Connect and point
quassum.com/apps/justscribe at the new site. The app's Settings link to
`quassum.com/apps/justscribe#credits`, `#support` and
`quassum.com/apps/justscribe/privacy`; the redirect must keep those resolving
(the new site has no `credits` or `support` anchors, so they need somewhere to
land), or released copies show dead links.

## CI

The CI workflow (`.github/workflows/ci.yml`) runs the unit tests inside the
sandboxed app, signed ad hoc so it carries its entitlements. The app's
deployment target is macOS 26.2, so the hosted `macos-26` runner must be at
least that; whether it is is only known after the first run, and the log's
`sw_vers` line (in *Select the newest installed Xcode*) shows it. The same job
tests the Sparkle key check, which needs macOS; the Linux job that runs the
other script tests skips it.

## When it fails

"Re-run" below means re-running the failed run while no newer release exists. A
run re-runs the commit it was started for, so once a later push has released,
re-running an older run is refused (the *does not descend* bullet below): push a
new commit or use **Run workflow** on `main` instead. *Build and publish*
repeats the version job's checks at its start, because "Re-run failed jobs"
re-runs it alone with the version it was given the first time.

- **missing repository secrets** — the first step names them; add and re-run.
- **The build failed** (in CI or in *Archive*) — the step after it, *Show the build
  errors*, lists the compiler errors and failed tests, and the full `build.log` is
  attached to the run as the `build-log` artifact.
- **no released Xcode installed** — the release builds only with a released Xcode,
  never a beta or release candidate, and the runner image had none. Wait for the
  image to gain one; CI, which may use a beta, is unaffected.
- **does not descend from the last release; refusing to release an older commit** —
  by design. The run was building a commit older than the latest release tag,
  almost always because an old failed run was re-run after a newer push had
  already released. Releasing it would ship an older build under a newer version
  and roll back every installed copy. Both jobs check this before building, so
  nothing was built or tagged; never delete the newer release's tag to get past
  it. Its changes are already on `main`, so push a new commit or use
  **Run workflow** on `main`; that run releases everything since the last tag.
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
  yet released. Usually `SPARKLE_PRIVATE_KEY` is not the exported key (44 base64
  characters), or it belongs to a different key pair than the app's
  `SUPublicEDKey` (the step says "refusing to sign" and prints both public keys;
  see [Sparkle](#3-sparkle-in-app-updates)). Fix the secret and re-run; nothing
  was tagged.
- **this commit was already tagged vX.Y.Z by an earlier attempt that did not
  finish publishing** — an earlier attempt of this same run tagged this very
  commit, then failed before the release was complete. *Build and publish* stops
  at its start, before building. (No newer release exists: that would have
  stopped the run with *does not descend* first.) The notarized DMG and zip are
  attached to the earlier attempt as artifacts (its run page, *Artifacts*).
  Publish all three — the DMG, the zip **and `appcast.xml`** — or installed
  copies will find no feed until the next release. Either publish them by hand as
  release `vX.Y.Z`, or delete the tag (`git push origin :refs/tags/vX.Y.Z`) and
  the release created from it, if one exists, then re-run. This is the only case
  in which deleting a release tag is right: the tag points at the commit being
  re-run, and its release was never published or lacks assets. If release
  `vX.Y.Z` is published with all three assets, delete nothing: the run failed
  after publishing (see *Rebuild the website failed*). A full re-run without
  deleting the tag prints "no code changes since vX.Y.Z" and releases nothing.
- **another commit was already released as vX.Y.Z; this run is stale, do not
  delete the tag** — by design, and nothing to recover. The run re-used a
  version computed before an earlier commit's run released that number
  ("Re-run failed jobs" keeps the *Decide the version* job's old outputs).
  Delete nothing: `vX.Y.Z` is another commit's published release. To release this
  commit's changes, re-run *all* jobs (the version is computed afresh), push a
  new commit, or use **Run workflow** on `main`.
- **Rebuild the website failed** — the release is already published; only the site's
  download button is stale. Re-run the build from the Worker's *Builds* page in the
  Cloudflare dashboard (re-running the Release workflow releases nothing: it prints
  "no code changes", or stops because this commit was already tagged or a newer
  release exists).
