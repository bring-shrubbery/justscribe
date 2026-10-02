/**
 * The path a built page is served at. Pages are built as flat files (privacy.html,
 * index.html) and served without the extension, so canonical URLs must drop it:
 * `/privacy.html` → `/privacy`, `/index.html` → `/`, `/guides/x.html` → `/guides/x`.
 */
export function servedPath(pathname: string): string {
  const path = pathname.replace(/\.html$/, '').replace(/\/index$/, '');
  return path === '' ? '/' : path;
}
