# Favicon & app-icon system — design

**Date:** 2026-06-05
**Status:** Approved (direction validated via visual brainstorming)

## Problem

The app's quality isn't reflected in its favicon. Two concrete failures today:

1. **The app references no favicon at all.** `root.html.heex` has no `<link rel="icon">`; the browser silently falls back to `/favicon.ico`, which is a 64×64 PNG *mislabeled* `.ico`.
2. **The marketing favicon is the detailed centaur-archer illustration scaled down.** Gorgeous at 512px, an illegible smudge at 16×16 — the size that actually matters in a browser tab.

A favicon is a **16px problem**. "Matching the app's quality" does not mean a higher-res render of the archer; it means a mark engineered to read at tab size, exported through a proper multi-resolution pipeline, and actually wired in.

## Decision

**A bold centaur silhouette, two-tone and per-mode, used at every size.**

- **Mark:** a thickened ("bold") silhouette of the existing centaur archer — the thin strokes (bow, arms, legs) fattened so the figure holds together as a confident mass instead of dissolving. Derived from the real art, not a new illustration.
- **Per-mode color on the tab favicon** (via `prefers-color-scheme`):
  - Light mode → **navy `#091F3F`** (the brand's light-logo color)
  - Dark mode → **cream `#F6E0C0`** (the brand's dark-icon color)
  These are the project's two existing brand treatments; the favicon reuses them rather than inventing new colors. Home-screen icons (apple-touch / PWA) can't observe page color-scheme, so they use the **cream-on-dark** treatment unconditionally — see the table below.
- **No accent split, no glyph fallback.** One mark at all sizes. We accept that at a literal 16px the silhouette reads as a "confident centaur mass" rather than a fully-resolved archer — validated and chosen knowingly over the crisper-but-off-brand Sagittarius glyph alternative.

### Considered and rejected

- **Detailed archer scaled down** — the current failure; illegible small.
- **Sagittarius arrow glyph** — razor-crisp at 16px and conceptually apt (the centaur archer *is* Sagittarius), but abstract; loses the figure. Kept as a documented fallback idea, not shipped.
- **Bold silhouette for large + glyph for small (the "combo")** — two marks by size. Rejected for brand simplicity: one mark everywhere.
- **Brand orange in both modes** — single signature color, but orange-on-white contrast is visibly weaker than navy-on-white.

## The icon system

| Artifact | Size(s) | Color treatment | Purpose |
|---|---|---|---|
| `favicon.svg` | vector / 512 source | **adaptive** navy↔cream | Modern browsers (primary) |
| `favicon.ico` | 16 + 32 + 48 | navy (static) | Legacy fallback |
| `apple-touch-icon.png` | 180×180 | cream on dark tile `#0D0F15` | iOS home screen (ignores alpha) |
| `icon-192.png` | 192×192 | cream on dark tile | PWA |
| `icon-512.png` | 512×512 | cream on dark tile | PWA / install |
| `icon-maskable-512.png` | 512×512 | cream on full-bleed dark, ~20% safe zone | PWA maskable (no clip on squircle/circle) |
| `site.webmanifest` | — | `theme_color`/`background_color` = `#0D0F15` | PWA metadata |

### How adaptivity works

`favicon.svg` embeds the bold silhouette **once** as a mask (white shape on black) and paints it with a single `<rect>` whose fill swaps by mode — no vectorizer required:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <style>
    rect { fill: #091F3F; }                                   /* light mode */
    @media (prefers-color-scheme: dark) { rect { fill: #F6E0C0; } }
  </style>
  <mask id="m"><image href="data:image/png;base64,…" width="512" height="512"/></mask>
  <rect width="512" height="512" mask="url(#m)"/>
</svg>
```

- **`.ico` is static** — it can't carry a media query, so it ships **navy**. The browsers that ignore SVG favicons and fall back to `.ico` are old and overwhelmingly light-themed, making navy the safe default. (Documented tradeoff, not an oversight.)
- **apple-touch / PWA icons are cream on a dark tile.** iOS/Android render these on a home screen, not a tab, and ignore transparency. Cream-on-`#0D0F15` matches the app's dark aesthetic and the existing `icon-512` treatment.

## Generation pipeline

A single reproducible, extensionless script — `scripts/gen-favicons` — regenerates **every** artifact from the source logo using only ImageMagick (already installed; **no new dependencies**). Rationale: bake the pipeline so the icon set is regenerable and never hand-assembled (aligns with the repo's "prefer scripts over AI workflows" and componentization bars).

Pipeline stages:
1. **Mask** — flatten `centaur-logo.png` on white, grayscale, threshold → solid black-on-white shape → extract alpha.
2. **Bold** — `-morphology Dilate Disk:5` to thicken (the "Bold" variant chosen in review). This is the single knob; document it inline.
3. **Adaptive SVG** — base64 the bold mask, inject into the `favicon.svg` template above.
4. **Raster exports** — navy `.ico` (16/32/48), cream-on-dark apple-touch (180), PWA (192/512), maskable (512 w/ safe zone).
5. **Manifest** — emit/refresh `site.webmanifest`.
6. Copy the marketing-facing set into `docs-site/assets/` so the landing page and app stay in lockstep.

## Wiring

**App** — add to the `<head>` in `lib/media_centaur_web/components/layouts/root.html.heex`:

```heex
<link rel="icon" href={~p"/favicon.ico"} sizes="48x48" />
<link rel="icon" href={~p"/images/favicon.svg"} type="image/svg+xml" />
<link rel="apple-touch-icon" href={~p"/images/apple-touch-icon.png"} />
<link rel="manifest" href={~p"/site.webmanifest"} />
```

**Static serving** — `static_paths/0` in `lib/media_centaur_web.ex` currently lists `~w(assets fonts images favicon.ico robots.txt)`. Add `site.webmanifest`. The `.svg`, apple-touch, and PWA PNGs live under `priv/static/images/` (already served).

**Marketing site (media-centaur.net)** — `docs-site/` deploys to GitHub Pages via `.github/workflows/pages.yml`; `media-centaur.net` is that site. `docs-site/index.html` already references `favicon.ico`, `favicon-32x32.png`, `favicon-16x16.png`, `apple-touch-icon.png`, `site.webmanifest` — the script regenerates all of these in `docs-site/assets/` with the new bold mark. **One HTML change needed:** add the adaptive SVG link (the marketing head currently lacks it):

```html
<link rel="icon" type="image/svg+xml" href="assets/favicon.svg" />
```

## Properties coverage

Where the new favicon applies across our public surfaces:

| Property | Controllable? | Action |
|---|---|---|
| **App** (Phoenix LiveView) | Yes | Add the four head `<link>`s + serve the artifacts (above). |
| **Marketing site / media-centaur.net** (`docs-site` → GitHub Pages) | Yes | Regenerate `docs-site/assets/` set + add the SVG link. |
| **GitHub Wiki** (`../media-centaur.wiki`) | **No** | Pure markdown rendered by github.com — GitHub serves its own favicon; no head we control. Not applicable. |
| **GitHub repo / README** | No | Rendered by github.com; no custom favicon possible. Not applicable. |
| **Internal mockups** (`mockups/**`) | n/a | Not public; out of scope. |

The only public surfaces where we control the favicon are the app and the marketing site — both covered. The wiki and repo pages are served by GitHub with GitHub's favicon and cannot be themed.

## Testing & verification

- **Automated:** the root layout renders on every page smoke test already; add one assertion in an existing web test that the rendered `<head>` carries the four icon `<link>`s (regression guard that wiring exists — this tests *rendered template output*, not a static config artifact, so it's distinct from the "no config-content grep tests" rule).
- **Visual:** the brainstorm renders are the acceptance bar; spot-check the generated `.ico`/SVG at 16/32/48 on light and dark before shipping.
- **Precommit:** must pass clean (format, credo, boundaries, sobelow, test, zero warnings).

## Out of scope / accepted tradeoffs

- **16px is a confident mass, not a resolved archer.** Chosen knowingly.
- **`.ico` fallback is navy-only** (no per-mode), affecting only legacy browsers.
- **SVG embeds a raster mask** rather than a vector path (potrace/inkscape absent). Crisp to 512; a future pure-vector path is an optional enhancement, not a blocker.
- **No change to the detailed archer hero art** — it remains the wordmark/hero asset; this work only touches the icon/favicon surface.

## File inventory

Generated/updated by `scripts/gen-favicons`:
- `priv/static/favicon.ico`
- `priv/static/images/favicon.svg`
- `priv/static/images/apple-touch-icon.png`
- `priv/static/images/icon-192.png`, `icon-512.png`, `icon-maskable-512.png`
- `priv/static/site.webmanifest`
- `docs-site/assets/` parity set (`favicon.svg`, `favicon.ico`, `favicon-16x16.png`, `favicon-32x32.png`, `apple-touch-icon.png`, `icon-192.png`, `icon-512.png`, `site.webmanifest`)

Hand-edited:
- `lib/media_centaur_web/components/layouts/root.html.heex` (head links)
- `lib/media_centaur_web.ex` (`static_paths/0` adds `site.webmanifest`)
- `docs-site/index.html` (add the `image/svg+xml` icon link)
- one web test (head-links assertion)
