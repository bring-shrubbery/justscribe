// @ts-check
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import sitemap from '@astrojs/sitemap';
import { defineConfig } from 'astro/config';

const site = 'https://justscribe.quassum.com';
const pages = fileURLToPath(new URL('./src/pages', import.meta.url));

/**
 * The `updated` date of every Markdown page, keyed by its URL, for the sitemap's <lastmod>.
 * Pages without one (the home page and the changelog, which change with every release)
 * get the build date.
 * @param {string} dir
 * @returns {Record<string, string>}
 */
function updatedDates(dir) {
  /** @type {Record<string, string>} */
  const dates = {};
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) Object.assign(dates, updatedDates(path));
    else if (entry.name.endsWith('.md')) {
      const match = /^updated:\s*"?(\d{4}-\d{2}-\d{2})"?\s*$/m.exec(readFileSync(path, 'utf8'));
      if (match?.[1]) dates[`${site}/${relative(pages, path).replace(/\.md$/, '')}`] = match[1];
    }
  }
  return dates;
}
const updated = updatedDates(pages);
const built = new Date().toISOString();

// https://astro.build/config
export default defineConfig({
  site,
  integrations: [
    sitemap({
      serialize(item) {
        const date = updated[item.url.replace(/\/$/, '')];
        item.lastmod = date ? new Date(`${date}T00:00:00Z`).toISOString() : built;
        return item;
      },
    }),
  ],
  output: 'static',
  // privacy.html rather than privacy/index.html: Workers assets then serve it at /privacy, the
  // canonical URL, instead of redirecting to /privacy/.
  build: { format: 'file' },
  trailingSlash: 'never',
  compressHTML: false,
});
