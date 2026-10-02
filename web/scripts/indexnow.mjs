#!/usr/bin/env node
// Tells IndexNow (Bing and the other search engines that share it) which pages of the
// site exist, so a new or changed page is fetched within minutes instead of at the next
// crawl. Run after a deploy: `npm run deploy` does. The key is not a secret: the file
// public/<key>.txt, served at the site's root, is what proves we may submit for this host.
// A failure is reported and ignored: the site is deployed either way.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const host = 'justscribe.quassum.com';
const key = '409e9020965a2864ba47e66867d99b89';
const sitemap = readFileSync(fileURLToPath(new URL('../dist/sitemap-0.xml', import.meta.url)), 'utf8');
const urlList = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1]);

try {
  const response = await fetch('https://api.indexnow.org/indexnow', {
    method: 'POST',
    headers: { 'content-type': 'application/json; charset=utf-8' },
    body: JSON.stringify({ host, key, keyLocation: `https://${host}/${key}.txt`, urlList }),
    signal: AbortSignal.timeout(15_000),
  });
  console.log(`IndexNow: submitted ${urlList.length} URLs, HTTP ${response.status}`);
} catch (error) {
  console.log(`IndexNow: not submitted (${error instanceof Error ? error.message : error})`);
}
