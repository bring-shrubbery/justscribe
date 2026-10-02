#!/usr/bin/env node
// Checks the built site in dist/ the way a search engine would meet it. Run after
// `npm run build`: npm run check:dist. Exits non-zero, listing every problem, when
//   - an internal link or image points at nothing in dist/ (and is not a _redirects rule);
//   - a page lacks exactly one <h1>, a <title>, a meta description, or a canonical URL
//     that matches where the page is served;
//   - a title is over 60 characters or a description is outside 70 to 160;
//   - two pages share a title or a description;
//   - a page's structured data does not parse;
//   - an indexable page is missing from the sitemap.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const dist = fileURLToPath(new URL('../dist', import.meta.url));
const site = 'https://justscribe.quassum.com';
const problems = [];
const problem = (page, text) => problems.push(`${page}: ${text}`);

function htmlFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return htmlFiles(path);
    return entry.name.endsWith('.html') ? [path] : [];
  });
}

/** The path a file is served at: dist/guides/x.html → /guides/x, dist/index.html → /. */
function served(file) {
  const path = `/${relative(dist, file).replace(/\\/g, '/')}`.replace(/\.html$/, '');
  return path.replace(/\/index$/, '') || '/';
}

const redirects = existsSync(join(dist, '_redirects'))
  ? readFileSync(join(dist, '_redirects'), 'utf8')
      .split('\n')
      .map((line) => line.trim().split(/\s+/)[0])
      .filter((source) => source?.startsWith('/'))
  : [];

function resolves(path) {
  const clean = decodeURIComponent(path.split('#')[0].split('?')[0]);
  if (clean === '' || clean === '/') return true;
  if (redirects.includes(clean)) return true;
  return existsSync(join(dist, clean)) || existsSync(join(dist, `${clean}.html`)) || existsSync(join(dist, clean, 'index.html'));
}

const attr = (tag, name) => new RegExp(`${name}="([^"]*)"`).exec(tag)?.[1];
const decode = (text) => text.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>');

const sitemap = existsSync(join(dist, 'sitemap-0.xml')) ? readFileSync(join(dist, 'sitemap-0.xml'), 'utf8') : '';
const titles = new Map();
const descriptions = new Map();
const files = htmlFiles(dist);

for (const file of files) {
  const page = served(file);
  const html = readFileSync(file, 'utf8');
  const noindex = /<meta name="robots" content="noindex"/.test(html);

  for (const tag of html.match(/<a [^>]*>/g) ?? []) {
    const href = attr(tag, 'href');
    if (href?.startsWith('/') && !resolves(href)) problem(page, `link to ${href} resolves to nothing`);
  }
  for (const tag of html.match(/<(img|link|source) [^>]*>/g) ?? []) {
    for (const value of [attr(tag, 'src'), attr(tag, 'href'), ...(attr(tag, 'srcset')?.split(',').map((s) => s.trim().split(' ')[0]) ?? [])]) {
      if (value?.startsWith('/') && !resolves(value)) problem(page, `asset ${value} resolves to nothing`);
    }
  }
  for (const tag of html.match(/<img [^>]*>/g) ?? []) {
    // A decorative image carries an empty alt, which is serialised as a bare `alt`.
    if (!/\salt(=|\s|>)/.test(tag)) problem(page, `image ${attr(tag, 'src')} has no alt attribute`);
  }

  const h1 = (html.match(/<h1[\s>]/g) ?? []).length;
  if (h1 !== 1) problem(page, `${h1} <h1> elements, expected 1`);

  const title = decode(/<title>([^<]*)<\/title>/.exec(html)?.[1] ?? '');
  const description = decode(attr(/<meta name="description"[^>]*>/.exec(html)?.[0] ?? '', 'content') ?? '');
  if (title === '') problem(page, 'no <title>');
  if (description === '') problem(page, 'no meta description');

  for (const block of html.match(/<script type="application\/ld\+json">[\s\S]*?<\/script>/g) ?? []) {
    try {
      JSON.parse(block.replace(/^<script[^>]*>/, '').replace(/<\/script>$/, ''));
    } catch (error) {
      problem(page, `structured data does not parse: ${error.message}`);
    }
  }

  if (noindex) continue;

  if (title.length > 60) problem(page, `title is ${title.length} characters, over 60: ${title}`);
  if (description.length < 70 || description.length > 160) problem(page, `description is ${description.length} characters, outside 70 to 160`);
  if (titles.has(title)) problem(page, `same title as ${titles.get(title)}`);
  if (descriptions.has(description)) problem(page, `same description as ${descriptions.get(description)}`);
  titles.set(title, page);
  descriptions.set(description, page);

  const canonical = attr(/<link rel="canonical"[^>]*>/.exec(html)?.[0] ?? '', 'href');
  const expected = page === '/' ? `${site}/` : `${site}${page}`;
  if (canonical !== expected) problem(page, `canonical is ${canonical}, expected ${expected}`);
  if (!sitemap.includes(`<loc>${expected}</loc>`)) problem(page, `missing from the sitemap as ${expected}`);
  if (!/<lastmod>/.test(sitemap)) problem(page, 'the sitemap has no <lastmod>');
}

if (problems.length > 0) {
  console.error(`${problems.length} problem(s) in dist/:`);
  for (const text of [...new Set(problems)]) console.error(`  ${text}`);
  process.exit(1);
}
console.log(`dist/ is consistent: ${files.length} pages, links, metadata, structured data and sitemap checked`);
