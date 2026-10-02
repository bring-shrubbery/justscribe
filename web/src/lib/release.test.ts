import { describe, expect, it } from 'vitest';
import { fetchLatestRelease, fetchReleases, formatMegabytes, noteBlocks, releaseFrom, releasesFrom, latestReleaseAPI, releasesAPI } from './release';

const v100 = {
  tag_name: 'v1.0.0',
  html_url: 'https://github.com/bring-shrubbery/justscribe/releases/tag/v1.0.0',
  assets: [
    { name: 'JustScribe-v1.0.0-macos-arm64.zip', browser_download_url: 'https://example.invalid/zip', size: 4271794 },
    { name: 'JustScribe-v1.0.0-macos-arm64.dmg', browser_download_url: 'https://example.invalid/dmg', size: 4326140 },
    { name: 'appcast.xml', browser_download_url: 'https://example.invalid/appcast', size: 900 },
  ],
};

function respond(status: number, body: unknown): typeof fetch {
  return async () => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

describe('releaseFrom', () => {
  it('picks the dmg asset', () => {
    expect(releaseFrom(v100)).toEqual({
      version: 'v1.0.0',
      notesURL: 'https://github.com/bring-shrubbery/justscribe/releases/tag/v1.0.0',
      dmgURL: 'https://example.invalid/dmg',
      dmgBytes: 4326140,
    });
  });

  it('is null without a dmg asset', () => {
    expect(releaseFrom({ ...v100, assets: v100.assets.filter((a) => !a.name.endsWith('.dmg')) })).toBeNull();
  });

  it('is null for a body that is not a release', () => {
    expect(releaseFrom(null)).toBeNull();
    expect(releaseFrom('nope')).toBeNull();
    expect(releaseFrom({ tag_name: 'v1', assets: 'not-an-array' })).toBeNull();
    expect(releaseFrom({ tag_name: '', html_url: 'x', assets: v100.assets })).toBeNull();
  });
});

describe('fetchLatestRelease', () => {
  it('returns the release on 200', async () => {
    expect(await fetchLatestRelease(respond(200, v100))).toMatchObject({ version: 'v1.0.0' });
  });

  it('asks the API with the github accept header and a user agent, and a bearer token when given', async () => {
    let seen: { url: string; headers: Headers } | undefined;
    const spy: typeof fetch = async (input, init) => {
      seen = { url: String(input), headers: new Headers(init?.headers) };
      return new Response(JSON.stringify(v100), { status: 200 });
    };
    await fetchLatestRelease(spy, 'tok');
    expect(seen?.url).toBe(latestReleaseAPI);
    expect(seen?.headers.get('accept')).toBe('application/vnd.github+json');
    expect(seen?.headers.get('user-agent')).toBe('justscribe-web');
    expect(seen?.headers.get('authorization')).toBe('Bearer tok');
  });

  it('sends no authorization header without a token', async () => {
    let auth: string | null = 'unset';
    const spy: typeof fetch = async (_input, init) => {
      auth = new Headers(init?.headers).get('authorization');
      return new Response(JSON.stringify(v100), { status: 200 });
    };
    await fetchLatestRelease(spy);
    expect(auth).toBeNull();
  });

  it('is null on a non-2xx status', async () => {
    expect(await fetchLatestRelease(respond(403, { message: 'rate limited' }))).toBeNull();
    expect(await fetchLatestRelease(respond(404, { message: 'Not Found' }))).toBeNull();
  });

  it('is null when the request throws', async () => {
    const failing: typeof fetch = async () => { throw new Error('offline'); };
    expect(await fetchLatestRelease(failing)).toBeNull();
  });

  it('gives the request an abort signal, so a hung API cannot stall the build', async () => {
    let signal: AbortSignal | null | undefined;
    const spy: typeof fetch = async (_input, init) => {
      signal = init?.signal;
      return new Response(JSON.stringify(v100), { status: 200 });
    };
    await fetchLatestRelease(spy);
    expect(signal).toBeInstanceOf(AbortSignal);
  });

  it('is null when the request times out', async () => {
    const timedOut: typeof fetch = async () => {
      throw new DOMException('The operation was aborted due to timeout', 'TimeoutError');
    };
    expect(await fetchLatestRelease(timedOut)).toBeNull();
  });

  it('is null when the body is not json', async () => {
    const html: typeof fetch = async () => new Response('<html>', { status: 200 });
    expect(await fetchLatestRelease(html)).toBeNull();
  });
});

describe('formatMegabytes', () => {
  it('rounds to one decimal in decimal megabytes', () => {
    expect(formatMegabytes(4326140)).toBe('4.3 MB');
    expect(formatMegabytes(950000)).toBe('1.0 MB');
    expect(formatMegabytes(12345678)).toBe('12.3 MB');
  });
});

describe('noteBlocks', () => {
  it('groups list items and keeps paragraphs, as plain text', () => {
    expect(noteBlocks('Intro line.\n\n- First **bold** item\n- A [link](https://example.invalid) and `code`\n\nAfter.')).toEqual([
      { kind: 'paragraph', text: 'Intro line.' },
      { kind: 'list', items: ['First bold item', 'A link and code'] },
      { kind: 'paragraph', text: 'After.' },
    ]);
  });

  it('drops the generated full-changelog line and blank items', () => {
    expect(noteBlocks('- One\n- \n\n**Full changelog**: https://github.com/x/y/compare/a...b')).toEqual([
      { kind: 'list', items: ['One'] },
    ]);
  });

  it('never passes markup through: angle brackets stay text', () => {
    expect(noteBlocks('- Add a <script>alert(1)</script> helper')).toEqual([
      { kind: 'list', items: ['Add a <script>alert(1)</script> helper'] },
    ]);
  });

  it('is empty for an empty body', () => {
    expect(noteBlocks('')).toEqual([]);
  });
});

const list = [
  { tag_name: 'v1.3.0', html_url: 'https://example.invalid/v1.3.0', published_at: '2026-10-01T20:58:31Z', body: '- First' },
  { tag_name: 'v1.3.1', html_url: 'https://example.invalid/v1.3.1', published_at: '2026-10-05T10:00:00Z', body: '- Second' },
  { tag_name: 'v1.4.0-beta', html_url: 'https://example.invalid/beta', published_at: '2026-10-06T10:00:00Z', body: '', prerelease: true },
  { tag_name: 'v9.9.9', html_url: 'https://example.invalid/draft', published_at: '2026-10-07T10:00:00Z', body: '', draft: true },
  { tag_name: 'no-date', html_url: 'https://example.invalid/x' },
];

describe('releasesFrom', () => {
  it('lists published releases newest first, without drafts, prereleases or malformed entries', () => {
    expect(releasesFrom(list).map((r) => r.version)).toEqual(['v1.3.1', 'v1.3.0']);
    expect(releasesFrom(list)[1]).toEqual({
      version: 'v1.3.0',
      publishedAt: '2026-10-01T20:58:31Z',
      notesURL: 'https://example.invalid/v1.3.0',
      notes: [{ kind: 'list', items: ['First'] }],
    });
  });

  it('is empty for a body that is not a list', () => {
    expect(releasesFrom(null)).toEqual([]);
    expect(releasesFrom({ message: 'rate limited' })).toEqual([]);
  });
});

describe('fetchReleases', () => {
  it('asks the releases API and returns the list', async () => {
    let url = '';
    const spy: typeof fetch = async (input) => {
      url = String(input);
      return new Response(JSON.stringify(list), { status: 200 });
    };
    expect((await fetchReleases(spy)).length).toBe(2);
    expect(url).toBe(releasesAPI);
  });

  it('is empty on a non-2xx status, a thrown request, or a body that is not json', async () => {
    expect(await fetchReleases(respond(403, { message: 'rate limited' }))).toEqual([]);
    const failing: typeof fetch = async () => { throw new Error('offline'); };
    expect(await fetchReleases(failing)).toEqual([]);
    const html: typeof fetch = async () => new Response('<html>', { status: 200 });
    expect(await fetchReleases(html)).toEqual([]);
  });
});
