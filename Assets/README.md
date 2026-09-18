# Hazmat — brand assets

Exported from the brand sheet (`hazmat-brand.html`), which lives outside this
repository and remains the source of truth for geometry, clear space and the
palette. Generated 2026-09-17.

## What is here, and what is not

This directory holds what the application bundle ships, plus the vector sources
those files came from:

- `Hazmat.icns` — the app icon, built from the brand's light tile.
- `menu-bar-template.png` / `@2x` — the status item's mark, 22 and 44 points.
- `svg/` — the vector sources, transparent background. `mark-*` are the five mark
  variants, `icon-*` are the app tiles, `menu-bar-template` is the status item,
  and the lockups and wordmark use live text in Space Mono Bold.
- `manifest.json` — the full export this set was taken from: every file it
  contains, with sizes, plus the palette and the wordmark font. The derived PNG
  farms, the favicons and the bundled font are not committed, because nothing in
  the product refers to them and shipping the font would carry an OFL obligation
  for an unused file. Re-export from the brand document to regenerate them.

## macOS menu bar

The status item ships `menu-bar-template.png` and its `@2x` as an `NSImage`
template image: the file is black plus alpha, and macOS supplies the tint, the
dark-mode appearance and the highlight inversion. Never colourise it in the app
and never draw it from code — it is exported so that nothing redraws the mark.
The `@2x` file is not decoration: it is what keeps the mark sharp on a Retina
menu bar, and the app looks the pair up by name so both are loaded.

## Rules that travel with the assets

- One accent (`#B46A46`); cream `#F7EEE6` and ink `#2B211C` carry everything else.
- Reverse (cream) mark is for ink surfaces only; never place it on mid-tones.
- Below 24 px, switch from `mark-primary` to `mark-glyph` (thicker strokes).
- Don't outline, rotate, recolour, or add effects to the mark; don't reset the
  wordmark in another face.
