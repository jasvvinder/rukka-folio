# Rukka Folio — Icon Package v1.2

Generated from the final sealed-mark geometry (Brand Guidelines v1.2, section 4.2).
Colours: indigo #2B3A67 · paper #F5F0E4 · bahi red #C1502E. Sealed state only —
the open state is an in-product animation, never a static icon.

## ios/
Drag `AppIcon.appiconset` into your Xcode asset catalog (replace the existing
AppIcon set). Covers iPhone, iPad, and the 1024 App Store marketing icon.
Full-bleed, no transparency, no pre-rounded corners — iOS applies its own mask.

## android/res/
Merge the `res/` folder into your app module. You get:
- Adaptive icon (Android 8+): `mipmap-anydpi-v26/` XML + `ic_launcher_foreground`
  PNGs (sized to the 66/108dp safe zone) + background colour resource.
- Themed icon (Android 13+): `ic_launcher_monochrome` layer, already wired.
- Legacy fallbacks: `ic_launcher` (rounded square) and `ic_launcher_round` per density.
- `playstore-icon-512.png` for the Play Console listing (uploaded there, not bundled).
Manifest should reference `@mipmap/ic_launcher` / `@mipmap/ic_launcher_round`.

## web/
Copy contents to `/icons/` on your site and paste `head-snippet.html` into <head>.
Includes multi-resolution favicon.ico (16/32/48), SVG favicon (crispest option,
modern browsers), apple-touch-icon (180), and PWA icons with proper
`maskable` variants declared in `site.webmanifest`. Adjust manifest name/paths
to your build.

## master/
The source SVGs. Edit these and re-render rather than editing PNGs:
- mark-sealed.svg — the brand mark (transparent background, 88 viewBox)
- mark-sealed-inverse.svg — for dark grounds
- mark-open.svg — in-product open state (reference for the animation)
- icon-fullbleed.svg — basis for all square icons
- icon-adaptive-foreground.svg / icon-maskable.svg — inset variants

## Production notes
- These are geometry-exact renders. Before store submission, have a designer do
  an optical pass (entry-stroke thickening below 24px is permitted per guidelines).
- Test the adaptive icon in circle, squircle and rounded-square masks on device.
- The monochrome layer is a silhouette; Android tints it to the user's theme.

## Changelog
- v1.2.3 — monochrome themed icon: seal at canonical position (half on strap, half on book), squeezed to r7 with an r10 clearance ring so the ring stops 2 units short of the untouched border. Mono-only size adaptation (colour marks keep r10). Applied at raster level — regenerate via gen_icons.py, do not hand-edit.
- v1.2 — strap inset 2 units top/bottom (y14–74): a hairline of book above and
  below the strap keeps the silhouette closed on paper/light backgrounds.
- v1.1 — initial package from the final mark geometry.
