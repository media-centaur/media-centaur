# Image Cache Specification

This document specifies how artwork images are stored, referenced, and loaded in the Media Centarr system.

---

## Hard Rules

1. **Images are served over HTTP at `/media-images/*`.** The LiveView UI uses `<img>` tags pointing to this endpoint. The backend resolves the image path across all configured watch directories.
2. **The database stores relative paths.** `contentUrl` is stored as `{uuid}/{role}.{ext}`. The serializer resolves to absolute filesystem paths when needed.

---

## Design Principles

- **One copy per role, sized for the target role.** Store a single image per role, resized at download time (via libvips in `ImageProcessor`) to the target dimensions for that role.
- **Remote URL + local path separation.** Each image record stores both the original remote URL and the local cached path. The backend writes `source_url` during metadata fetch and `content_url` after the file is downloaded.
- **Multiple roles per entity, one row each.** The `library_images` table has many rows per entity, one per role. Adding a new role does not require a schema migration — just write a row with the new `role` value.
- **UUID-keyed directories.** Each entity's images live under `data/images/{entity_id}/`. The entity UUID is the sole key — no name-based paths.

---

## Image Schema

Each row in `library_images` (Ecto schema `MediaCentarr.Library.Image`)
holds one image for one entity. See the schema module for the full
field list.

Key fields for image caching:

- **`source_url`** — the canonical remote source URL (written by the
  manager, used for re-download)
- **`content_url`** — stored as a relative path (`{uuid}/poster.jpg`).
  Resolved to an absolute filesystem path at serve time. `nil` until
  download completes.
- **`role`** — `"poster"`, `"backdrop"`, `"logo"`, or `"thumb"` (see
  Image Roles below)

---

## Image Roles

| Role | `name` value | Aspect ratio | Usage |
|------|-------------|--------------|-------|
| Poster | `"poster"` | 2:3 portrait | Grid card artwork; required for v1 |
| Backdrop | `"backdrop"` | 16:9 landscape | Detail view hero background |
| Logo | `"logo"` | variable, transparent | Detail view title overlay |
| Thumbnail | `"thumb"` | 16:9 | Episode thumbnails in TVSeries |

**v1 requirement:** Only `poster` is needed for the grid card view. Backdrop and logo are used in detail hero layouts.

### Roles by Entity Type

| Role | Movie | TVSeries | VideoObject |
|------|-------|----------|-------------|
| `poster` | TMDB poster (2:3) | TMDB poster (2:3) | Thumbnail |
| `backdrop` | TMDB backdrop (16:9) | TMDB backdrop (16:9) | — |
| `logo` | TMDB logo (transparent) | TMDB logo (transparent) | — |
| `thumb` | — | Episode thumbnail | — |

---

## Directory Structure

Each watch directory has its own image cache. By default, images are stored at `{watch_dir}/.media-centarr/images/`. Users can override this per watch directory from the UI — **Settings → Library → Watch Directories** exposes an advanced *images directory* field on each entry for putting the artwork cache on a separate volume (e.g. SSD). Watch directories are DB-managed since v0.14.0; the TOML is not consulted for them.

```
/mnt/videos/.media-centarr/
└── images/
    ├── 550e8400-e29b-41d4-a716-446655440001/   # Sample Movie (entity)
    │   ├── poster.jpg
    │   └── backdrop.jpg
    ├── 660a1200-b33c-42e5-b819-557766550010/   # Child Movie (movie)
    │   └── poster.jpg
    └── ...

/mnt/nas/TV/.media-centarr/
└── images/
    ├── 550e8400-e29b-41d4-a716-446655440004/   # Sample Show (entity)
    │   └── poster.jpg
    ├── 770b2300-c44d-53f6-c920-668877660020/   # S01E03 (episode)
    │   └── thumb.jpg
    └── ...
```

- One subdirectory per owner (entity, child movie, or episode), named by the owner's UUID.
- Filename is `{role}.{ext}` — extension matches the source format (`.jpg` or `.png`).
- The database stores relative paths (`{uuid}/{role}.{ext}`). The serializer resolves to absolute filesystem paths when needed.
- Staging directories for in-progress downloads are created at `{images_dir}/partial-downloads/` (inside the image cache, not alongside it) and cleaned up after pipeline completion and on application startup. See `MediaCentarr.Config.staging_base_for/1`.

---

## Remote URL Patterns

The manager app uses these patterns when downloading images:

**Movies and TV Series (TMDB):**

| Role | URL pattern |
|------|-------------|
| Poster | `https://image.tmdb.org/t/p/original/{poster_path}` |
| Backdrop | `https://image.tmdb.org/t/p/original/{backdrop_path}` |
| Logo | `https://image.tmdb.org/t/p/original/{logo_path}` |

`{poster_path}` etc. come from the TMDB API response (e.g. `/1E5baAaEse26fej7uHcjOgEE2t2.jpg`).

All image downloads — whether driven by the Pipeline (`MediaCentarr.Pipeline.ImageProcessor`) or by `ReleaseTracking.ImageStore` — go through the shared `MediaCentarr.Images` facade:

- `Images.download/3` — download + resize via libvips. Used for poster / backdrop / logo / thumb where the on-disk size must match the target role.
- `Images.download_raw/2` — raw bytes without processing. Used where a downstream consumer needs the unmodified source.

No caller writes an HTTP download inline. Resize targets per role are defined in `MediaCentarr.Pipeline.ImageProcessor`.

**Video Objects:** No standard source. User-provided thumbnails or frames extracted from video.

---

## Responsibilities

### Backend

- Query external APIs to get image URLs
- Create `ImageObject` entries with `url` populated (remote TMDB URL) and `contentUrl: null`
- Download images to `{images_dir}/{uuid}/{role}.{ext}`, where `images_dir` is resolved per watch directory via `Config.images_dir_for/1`
- Update `contentUrl` in the `ImageObject` entry with the local path after successful download
- Never overwrite a locally modified image without user confirmation
- Serve images over HTTP at `/media-images/*` (see [HTTP Endpoint](#http-endpoint) below)

### LiveView UI

- Use `<img>` tags with `/media-images/{uuid}/{role}.{ext}` paths
- If an image is missing, render a solid-color placeholder — no crash, no error

---

## HTTP Endpoint

The backend serves images over HTTP at `/media-images/*` via `ImageServerPlug`. The LiveView UI uses this endpoint for all `<img>` tags.

**Request:** `GET /media-images/{uuid}/{role}.{ext}` (e.g. `/media-images/550e8400-.../poster.jpg`)

The plug searches all configured watch directories' image caches for the requested file and returns the first match. Returns 404 if the file is not found in any cache. Path traversal (`..`) is rejected with 400.

---

## Fallback Behavior

The UI must handle missing images gracefully at every level:

1. Entity has no `image` array or empty array → solid-color placeholder
2. No entry with `name == "poster"` → solid-color placeholder
3. `contentUrl` field is absent → solid-color placeholder
4. HTTP endpoint returns 404 → solid-color placeholder

Fallback colors are assigned per `MediaKind` for visual distinction.
