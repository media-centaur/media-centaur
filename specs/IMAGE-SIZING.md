# Image Sizing Specification

This document specifies the recommended source dimensions for every image role in the Media Centaur system. It provides the data the backend needs to generate appropriately-sized images, eliminating the memory waste of decoding full-resolution source images for small UI elements.

Companion to [`IMAGE-CACHING.md`](IMAGE-CACHING.md), which defines image roles, directory layout, and caching rules. This document adds **sizing requirements** per role.

---

## Hard Rules

1. **Source images must not exceed the recommended dimensions.** The backend must resize images to the sizes specified in this document before writing them to the image cache. Oversized images waste CPU memory at decode time and provide no visual benefit.
2. **Aspect ratios must be preserved.** Resizing is always proportional — never stretch or crop (except for logos, which use longest-edge sizing).
3. **The frontend does not resize images.** It decodes the file as-is and relies on GPU texture scaling for rendering. Sizing is the backend's responsibility.

---

## Scaling Model

The frontend uses a rem-based scaling system. All UI dimensions are specified in rems, converted to pixels at render time.

```
effective_rem = 16.0 × (viewport_height / 1080.0) × zoom
```

The `card_size`, `text_size`, and `content_width` knobs further scale specific element categories. See the frontend's `BOX-MODEL.md` for the full pipeline.

### Reference Configurations

| Configuration | Viewport | zoom | card_size | content_width | effective_rem |
|---------------|----------|------|-----------|---------------|---------------|
| 1080p default | 1920×1080 | 1.0 | 1.0 | 1.0 | 16.0 px |
| 1080p max | 1920×1080 | 1.5 | 1.3 | 1.3 | 24.0 px |
| 4K default | 3840×2160 | 1.0 | 1.0 | 1.0 | 32.0 px |
| 4K max | 3840×2160 | 1.5 | 1.3 | 1.3 | 48.0 px |

**"Max" configuration** represents a reasonable accessibility/TV-viewing-distance scenario: zoom=1.5, card_size=1.3, content_width=1.3. It is the sizing target — source images must look sharp at these dimensions.

---

## Rendering Sites

Every location where an image is rendered in the UI, with its rem dimensions, object-fit mode, and computed pixel dimensions across all reference configurations.

### Backdrop (`ObjectFit::Cover`)

Backdrops are cropped to fill their container. The source must be at least as large as the largest rendered container to avoid upscaling artifacts.

| Context | Rem dimensions | 1080p default | 1080p max | 4K default | 4K max |
|---------|----------------|---------------|-----------|------------|--------|
| Grid card | card_w × card_w×0.5625 | 220×124 | 429×241 | 440×248 | 858×483 |
| Hero section (18 rem) | detail_w × 18rem | 680×288 | 1326×432 | 1360×576 | 2652×864 |
| Banner section (20 rem) | detail_w × 20rem | 680×320 | 1326×480 | 1360×640 | 2652×960 |
| Movie list thumbnail | 7rem × 4rem | 112×64 | 168×96 | 224×128 | 336×192 |

Largest rendering: **2652×960 px** (banner at 4K max).

### Logo (`ObjectFit::Contain`)

Logos are scaled to fit within their bounding box, preserving aspect ratio. The source must cover the largest bounding box dimension to avoid upscaling.

| Context | Rem dimensions | 1080p default | 1080p max | 4K default | 4K max |
|---------|----------------|---------------|-----------|------------|--------|
| Grid card | card_w×0.9 × card_h×0.9 | 198×111 | 386×217 | 396×223 | 772×434 |
| Hero overlay | max_w 24rem × h 6rem | 384×96 | 576×144 | 768×192 | 1152×288 |
| Banner overlay | w 16rem × h 5rem | 256×80 | 384×120 | 512×160 | 768×240 |

Largest bounding box: **1152 px wide** (hero) × **434 px tall** (grid card).

### Poster (`ObjectFit::Cover`)

Posters are cropped to fill their container. Standard aspect ratio is 2:3 portrait.

| Context | Rem dimensions | 1080p default | 1080p max | 4K default | 4K max |
|---------|----------------|---------------|-----------|------------|--------|
| Hero detail (left column) | detail_w / 3 | 227 wide | 442 wide | 453 wide | 884 wide |
| Movie list thumbnail | 3.5rem × 5rem | 56×80 | 84×120 | 112×160 | 168×240 |

Largest rendering: **884 px wide** (hero at 4K max). At 2:3 aspect: 884×1326.

### Episode / Child Thumbnail (`ObjectFit::Cover`)

Small 16:9 thumbnails in episode and movie lists.

| Context | Rem dimensions | 1080p default | 1080p max | 4K default | 4K max |
|---------|----------------|---------------|-----------|------------|--------|
| Episode list | 7rem × 4rem | 112×64 | 168×96 | 224×128 | 336×192 |
| Movie list | 7rem × 4rem | 112×64 | 168×96 | 224×128 | 336×192 |

Largest rendering: **336×192 px** (4K max).

---

## Recommended Source Dimensions

Each recommendation includes 25% headroom above the largest rendered size to accommodate future layout growth without requiring a re-download pipeline.

| Role | Recommended size | Aspect ratio | Rationale |
|------|-----------------|--------------|-----------|
| **Backdrop** | **3360×1890** | 16:9 | Largest render 2652×960 + 25% headroom → 3315 wide. Rounded to clean 16:9 dimensions. |
| **Logo** | **Longest edge 1440 px** | Native (variable) | Largest bounding box 1152 wide + 25% headroom → 1440. Scale proportionally, preserving native aspect ratio. |
| **Poster** | **1120×1680** | 2:3 | Largest render 884 wide + 25% headroom → 1105. Rounded to clean 2:3 dimensions. |
| **Thumbnail** | **480×270** | 16:9 | Largest render 336×192 + 25% headroom → 420×240. Rounded up to clean 16:9 dimensions (~43% headroom). |

### TMDB Size Selection

The backend downloads from TMDB using size variants in the URL path. Recommended TMDB sizes to match the above:

| Role | TMDB size | Typical resolution | Notes |
|------|-----------|-------------------|-------|
| Backdrop | `w1280` or `original` | 1280×720 or 3840×2160 | `original` exceeds recommendation for some sources; prefer `w1280` and let the backend upscale only if needed, or use `original` and resize down. |
| Logo | `w500` or `original` | Variable | `w500` is often sufficient; `original` may exceed 1440 px and should be resized. |
| Poster | `w780` | 780×1170 | Slightly under the 1120 recommendation; `original` (typically 2000×3000) should be resized down. |
| Thumbnail | `w300` or `w780` | 300×169 or 780×439 | `w300` is under recommendation; `w780` is over — resize to 480×270. |

The backend should download at a size at or above the recommendation, then resize to the exact recommended dimensions before writing to the image cache.

---

## Memory Impact

Estimated savings from resizing the current library (583 images) from full-resolution TMDB originals to recommended sizes.

Decoded memory = width × height × 4 bytes (RGBA).

| Role | Count | Current decoded (MB) | Recommended decoded (MB) | Savings |
|------|-------|---------------------|--------------------------|---------|
| Backdrop | 83 | 1,959 | 2,106 (3360×1890) | +147 (larger — see note) |
| Logo | 70 | 730 | ~28 (avg 1440×200) | **702 (96%)** |
| Poster | 83 | 1,397 | 593 (1120×1680) | **804 (58%)** |
| Thumbnail | 347 | 5,508 | 172 (480×270) | **5,336 (97%)** |
| **Total** | **583** | **9,594** | **~2,899** | **~6,695 (70%)** |

**Backdrop note:** The current TMDB `original` backdrops average smaller than 3360×1890 because many sources are 1920×1080 or 3072×1920. The recommendation is sized for the detail view hero/banner (2652×960 max rendering). For grid cards alone, 858×483 would suffice — see Future Optimizations.

---

## Future Optimizations

These are not part of this specification but are noted for future consideration.

### Card-size backdrop variant

Grid cards only render backdrops at 858×483 (4K max). A second `backdrop-card` role at 960×540 would reduce grid-loaded backdrop memory from 2,106 MB to ~163 MB (for the current library), bringing total decoded memory to ~956 MB. This requires:
- A new image role in [`IMAGE-CACHING.md`](IMAGE-CACHING.md)
- Backend pipeline to generate both variants
- Frontend to select the appropriate variant per rendering context

### Lazy loading

Currently all entity images are decoded at library load time. Decoding only visible grid cards (and prefetching neighbors) would cap steady-state memory regardless of library size.

### GPU texture format

The frontend decodes to RGBA in CPU memory before uploading to GPU. A compressed GPU texture format (BC7, ASTC) would reduce both CPU decode memory and GPU VRAM, but requires GPUI support.
