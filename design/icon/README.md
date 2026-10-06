# App icon

Design **A2 · Ball + MT** (SB-1280): white football over bold "MT" on navy, amber dot top-right.

| Role | Colour |
|---|---|
| Background | `#152C75` (web `brand-700`) |
| Ball, MT | `#FFFFFF` |
| Dot | `#F59E0B` (web `accent-400`) |

## Regenerate

```bash
swift scripts/make-icon.swift
```

Writes `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024, opaque) and the SVGs here.
All geometry lives in that script; edit it there, not the outputs.

## Files

- `icon.svg`: the whole icon, for previews.
- `layers/ball.svg`, `layers/dot.svg`, `layers/mt.svg`: one layer each on a transparent 100×100 canvas, text
  outlined, for Icon Composer.
- `fonts/ArchivoBlack-Regular.ttf`: the "MT" typeface (SIL Open Font License, `fonts/OFL.txt`). Only the script
  reads it; the app doesn't ship it.

## Liquid Glass version (optional)

The asset-catalog PNG is what ships today. For the layered Liquid Glass icon:

1. Open Icon Composer (`/Applications/Xcode.app/Contents/Applications/Icon Composer.app`).
2. Background fill `#152C75`; drop in `ball.svg`, `mt.svg`, then `dot.svg` as separate layers.
3. Check the default, dark, tinted and clear previews.
4. Save as `App/Resources/AppIcon.icon` and wire it into `project.yml` (separate change).
