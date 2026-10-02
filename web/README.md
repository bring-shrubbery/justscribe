# JustScribe website

The site at https://justscribe.quassum.com: an Astro static site that offers the latest
release for download and owns the URLs the app depends on. `/appcast.xml` redirects to the
release feed on GitHub, and the app's Settings link to `/privacy`, `/terms`, `/support` and
`/#credits`, so those paths must keep working.

## Pages

- `src/pages/index.astro`: the home page.
- `src/pages/*.md` and `src/pages/guides/*.md`: every other page is a Markdown file whose
  frontmatter is its metadata (`title` under 60 characters, `description` of 70 to 160,
  `heading`, `updated`, optional `faq` and `download: false`), rendered by
  `src/layouts/Page.astro`. To add a page, add a file, then link it from
  `src/components/Footer.astro` and `public/llms.txt`.
- `src/pages/changelog.astro`: generated from GitHub releases at build time.
- The comparison pages state facts about other products. Each names its sources and the month
  they were checked; re-check them, and bump `updated`, when you touch the page.

## Develop

```sh
cd web
npm install
npm run dev        # http://localhost:4321
npm run check      # astro check (types)
npm test           # vitest
npm run build      # writes dist/
npm run check:dist # links, titles, descriptions, canonicals, structured data, sitemap
npm run preview    # serves dist/ (without the _redirects rules)
```

The download button is rendered at build time from the latest GitHub release. When the API is
unreachable or throttled the button links to the Releases page instead; the build never fails
because of it. Set `GITHUB_TOKEN` in the environment (any token, no scopes needed) to lift the
unauthenticated rate limit; Workers Builds share egress addresses, so set it there too.

## Deploy (Cloudflare Workers Builds)

The Worker `justscribe-web` exists (account Quassum MB) and was first deployed by hand on
2026-10-02. To deploy by hand again, for example after a release while the deploy hook is not
set up:

```sh
cd web
npx wrangler login     # once per machine
npm run deploy         # build, check dist/, deploy, then tell IndexNow which pages exist
```

IndexNow is how Bing and the search engines that share it learn about new or changed pages
within minutes. `public/<key>.txt` proves we may submit for this host; the key is not a secret.

The custom domain is part of `wrangler.jsonc` (`routes`), so a deploy creates the DNS record
and certificate itself; the `quassum.com` zone must be on the same account.

To have Cloudflare build the site on its own, connect the repository once in the dashboard:

1. **Workers & Pages → `justscribe-web` → Settings → Builds → Connect** →
   `bring-shrubbery/justscribe`. The Worker's name must match `name` in `wrangler.jsonc`, or
   Cloudflare's autofix opens a pull request to rename it.
2. Build configuration: root directory `web`, build command `npm run build`, deploy command
   `npx wrangler deploy && node scripts/indexnow.mjs`, production branch `main`. Leave non-production branch builds off.
   Under *Build watch paths*, include `web/*` so pushes that do not touch the site skip the
   build.
3. Optionally add a build environment variable `GITHUB_TOKEN` (see above).
4. **Settings → Builds → Deploy Hooks → Create** for branch `main`, then in the repository:
   `gh secret set CF_DEPLOY_HOOK_URL` and paste the hook URL. The release workflow POSTs it
   after every app release so the download button shows the new version.

With that watch path, every push to `main` that touches `web/` rebuilds the site; without it,
every push does. `wrangler.jsonc` is assets-only:
there is no Worker code, only `dist/` and the `_redirects` file in `public/`.

## Check a deployment

```sh
curl -I https://justscribe.quassum.com/appcast.xml   # 302 to the GitHub asset
curl -I https://justscribe.quassum.com/download      # 302 to the Releases page
```
