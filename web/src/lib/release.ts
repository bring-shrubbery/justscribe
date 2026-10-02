/**
 * The latest GitHub release, read once at build time for the download control.
 * Every failure is `null`: the page then links to the Releases page, and the
 * build never depends on the API being up or unthrottled.
 */

export interface Release {
  /** The tag, e.g. `v1.0.0`. */
  version: string;
  /** The release page, for "Release notes". */
  notesURL: string;
  /** The `-macos-arm64.dmg` asset. */
  dmgURL: string;
  dmgBytes: number;
}

export const repository = 'bring-shrubbery/justscribe';
export const latestReleaseAPI = `https://api.github.com/repos/${repository}/releases/latest`;
export const releasesPage = `https://github.com/${repository}/releases/latest`;

const dmgSuffix = '-macos-arm64.dmg';

interface Asset { name: string; browser_download_url: string; size: number }

function isAsset(value: unknown): value is Asset {
  if (typeof value !== 'object' || value === null) return false;
  const a = value as Record<string, unknown>;
  return typeof a.name === 'string' && typeof a.browser_download_url === 'string' && typeof a.size === 'number';
}

/** The release described by an API response body, or null when it is not one we can use. */
export function releaseFrom(json: unknown): Release | null {
  if (typeof json !== 'object' || json === null) return null;
  const r = json as Record<string, unknown>;
  if (typeof r.tag_name !== 'string' || r.tag_name === '') return null;
  if (typeof r.html_url !== 'string' || !Array.isArray(r.assets)) return null;
  const dmg = r.assets.find((a) => isAsset(a) && a.name.endsWith(dmgSuffix));
  if (!isAsset(dmg)) return null;
  return { version: r.tag_name, notesURL: r.html_url, dmgURL: dmg.browser_download_url, dmgBytes: dmg.size };
}

/**
 * Fetches the latest release. `token`, when given, authenticates the request:
 * Workers Builds share egress addresses, and the unauthenticated limit is per address.
 * The request gives up after ten seconds, so a hung API cannot stall the build.
 */
export async function fetchLatestRelease(fetchImpl: typeof fetch = fetch, token?: string): Promise<Release | null> {
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'justscribe-web',
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  try {
    const response = await fetchImpl(latestReleaseAPI, { headers, signal: AbortSignal.timeout(10_000) });
    if (!response.ok) return null;
    return releaseFrom(await response.json());
  } catch {
    return null;
  }
}

/** `4326140` → `4.3 MB` (decimal megabytes, one decimal, as Finder shows). */
export function formatMegabytes(bytes: number): string {
  const rounded = Math.round((bytes / 1_000_000) * 10) / 10;
  return `${rounded.toFixed(1)} MB`;
}

/** One published release, for the changelog page. */
export interface ReleaseEntry {
  /** The tag, e.g. `v1.3.0`. */
  version: string;
  /** ISO 8601 publication time. */
  publishedAt: string;
  notesURL: string;
  /** The release body split into paragraphs and list items, as plain text. */
  notes: NoteBlock[];
}

export type NoteBlock = { kind: 'paragraph'; text: string } | { kind: 'list'; items: string[] };

export const releasesAPI = `https://api.github.com/repos/${repository}/releases?per_page=30`;

/**
 * A release body as plain-text blocks. Release bodies are short Markdown: paragraphs and
 * `- ` lists. Inline Markdown is reduced to its text (links keep their label, emphasis and
 * code lose their markers), so nothing from the body is ever rendered as HTML. The
 * generated "Full changelog" line is dropped; the page links to the release instead.
 */
export function noteBlocks(body: string): NoteBlock[] {
  const plain = (text: string) =>
    text
      .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
      .replace(/(\*\*|__|`)/g, '')
      .trim();
  const blocks: NoteBlock[] = [];
  for (const raw of body.split(/\r?\n/)) {
    const line = raw.trim();
    if (line === '' || /^\*\*Full changelog\*\*/i.test(line)) continue;
    const item = /^[-*](?:\s+(.*))?$/.exec(line);
    if (item) {
      const text = plain(item[1] ?? '');
      if (text === '') continue;
      const last = blocks[blocks.length - 1];
      if (last?.kind === 'list') last.items.push(text);
      else blocks.push({ kind: 'list', items: [text] });
    } else {
      const text = plain(line.replace(/^#+\s*/, ''));
      if (text !== '') blocks.push({ kind: 'paragraph', text });
    }
  }
  return blocks;
}

/** The published releases described by an API response body, newest first; drafts and prereleases are left out. */
export function releasesFrom(json: unknown): ReleaseEntry[] {
  if (!Array.isArray(json)) return [];
  const entries: ReleaseEntry[] = [];
  for (const value of json) {
    if (typeof value !== 'object' || value === null) continue;
    const r = value as Record<string, unknown>;
    if (r.draft === true || r.prerelease === true) continue;
    if (typeof r.tag_name !== 'string' || typeof r.html_url !== 'string' || typeof r.published_at !== 'string') continue;
    entries.push({
      version: r.tag_name,
      publishedAt: r.published_at,
      notesURL: r.html_url,
      notes: noteBlocks(typeof r.body === 'string' ? r.body : ''),
    });
  }
  return entries.sort((a, b) => b.publishedAt.localeCompare(a.publishedAt));
}

/** Fetches the release list. Every failure is an empty list: the changelog then links to GitHub. */
export async function fetchReleases(fetchImpl: typeof fetch = fetch, token?: string): Promise<ReleaseEntry[]> {
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'justscribe-web',
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  try {
    const response = await fetchImpl(releasesAPI, { headers, signal: AbortSignal.timeout(10_000) });
    if (!response.ok) return [];
    return releasesFrom(await response.json());
  } catch {
    return [];
  }
}

let latest: Promise<Release | null> | undefined;
/** The latest release, fetched once per build however many pages show the download control. */
export function latestRelease(token?: string): Promise<Release | null> {
  latest ??= fetchLatestRelease(fetch, token);
  return latest;
}
