# Brand assets

Exported from the Hazmat brand sheet, which lives outside this repository and
remains the source of truth for geometry, clear space and the palette.

- `Hazmat.icns` — the app icon, built from the brand's light tile.
- `menu-bar-template.png` and `@2x` — the menu-bar mark at 22 and 44 points.
  Pure black plus alpha: the system tints it for appearance and highlight, so it
  is never recoloured in the app and never used as a template-image substitute.

`Scripts/make-dev-bundle.sh` copies all three into the development bundle's
`Contents/Resources` and names `Hazmat.icns` in the bundle's property list.
