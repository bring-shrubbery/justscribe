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
 */
export async function fetchLatestRelease(fetchImpl: typeof fetch = fetch, token?: string): Promise<Release | null> {
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'justscribe-web',
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  try {
    const response = await fetchImpl(latestReleaseAPI, { headers });
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
