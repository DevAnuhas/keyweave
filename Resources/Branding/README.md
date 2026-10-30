# KeyWeaver artwork

`KeyWeaverIcon.png` is the 1024-pixel app-icon master. `KeyWeaverMark.png` is the transparent monochrome logo; the menu-bar template uses the same face and woven W. `Scripts/generate-brand-assets.sh` produces native icon sizes, ICNS and 18/36-pixel template images with macOS `sips`/`iconutil`.

Generated with the built-in `image_gen` tool on 2026-10-30, then mechanically resized for packaging. The [actual Cotypist icon in its official press kit](https://cotypist.app/img/press/cotypist-icon-1024.png) was inspected as visual inspiration. The reference image remains outside git; only the newly generated artwork is included. The design changes the silhouette/composition to an upright, broad robot with a woven-W smile and no gripping hands or vertical bar.

## App-icon prompt

```text
Use case: logo-brand. Asset type: final 1024×1024 macOS application icon for KeyWeaver, an on-device writing autocomplete app. Create an original, highly polished icon. Visual inspiration observed from the real Cotypist icon: a friendly white ceramic robot, dark face, luminous cyan accents and a deep blue rounded-square app tile. Create a clearly different design: an upright, front-facing, broad softly squared robot head with a pearlescent ceramic rim, a dark midnight visor, two confident small cyan eyes, and a distinctive simple woven-W shaped cyan smile made from one clean ribbon. No hands, no gripping a vertical bar, no tilted oval head, no copied mascot silhouette. Center the large memorable robot head on a deep navy native macOS rounded-square tile with subtle blue/teal lighting and restrained dimensional highlights. Strong silhouette, few large shapes, balanced padding, legible at 32 pixels. Refined native Mac craft, not a busy illustration. No text, no letters printed on the tile, no watermark, no mockup scene. The tile occupies about 90 percent of the canvas with transparent space outside its rounded corners; keep the whole tile and subtle edge shadow within the canvas.
```

## Logo/menu-template prompt

The new app icon was supplied as the image reference; transparent output was requested for both generations.

```text
Use case: logo-brand / precise-object-edit. Input image is the new KeyWeaver app icon, an identity reference. Create its matching final monochrome macOS menu-bar template icon and standalone logo mark. Preserve only the identity of the face: two small friendly arch-shaped eyes above the distinctive woven W smile. Isolate those three bold filled shapes, redraw as absolutely solid pure black with clean smooth edges on a genuinely transparent background. No robot head outline, no ears, no pedestal, no app tile, no border, no text. Simplify the W smile to a single connected broad ribbon silhouette; remove shading and use a tiny clean negative-space notch only if needed to suggest the weave. Keep it recognizable and strongly legible when reduced to an 18-pixel macOS menu bar glyph. Center the compact eye-and-W face, about 78 percent of square canvas width and 62 percent height. Uniform black fill including the eyes; no gray, no gradients, no glow, no shadows, no background.
```
