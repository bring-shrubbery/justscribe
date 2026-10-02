import { describe, expect, it } from 'vitest';
import { servedPath } from './url';

describe('servedPath', () => {
  it('drops the extension of a flat page', () => {
    expect(servedPath('/privacy.html')).toBe('/privacy');
    expect(servedPath('/guides/grammar-correction.html')).toBe('/guides/grammar-correction');
  });

  it('serves the index at the root', () => {
    expect(servedPath('/index.html')).toBe('/');
    expect(servedPath('/')).toBe('/');
  });

  it('leaves a path without an extension alone, as in the dev server', () => {
    expect(servedPath('/privacy')).toBe('/privacy');
  });
});
