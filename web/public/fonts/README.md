# Fonts

Inter (Regular, Medium, SemiBold) and JetBrains Mono NL Regular, subset to Latin plus the
symbols the page uses (· →) and packed as woff2. Copied from the neural-sheet website
(`../neural-sheet/web/public/fonts`). Licences: Inter-LICENSE.txt, JetBrainsMono-OFL.txt
(both OFL 1.1).

The subset covers U+0000-00FF, U+0152-0153, U+2000-206F, U+2190-2193, U+2212, U+21E7,
U+2318, U+2325 and U+232B. It has no ⌃ (U+2303), which is why the page writes the shortcut
in words. To add a character, re-subset the TTFs the neural-sheet app bundles
(`app/NeuralSheet/Resources/Fonts` in that repository):

```sh
pip install fonttools brotli
pyftsubset <path-to>/Inter-Regular.ttf \
  --unicodes="U+0000-00FF,U+0152-0153,U+2000-206F,U+2190-2193,U+2212,U+21E7,U+2318,U+2325,U+232B,<new>" \
  --layout-features='*' --flavor=woff2 --no-hinting --output-file=Inter-Regular.woff2
```
