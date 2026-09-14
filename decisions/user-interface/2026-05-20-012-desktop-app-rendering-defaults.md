---
status: accepted
date: 2026-05-20
amended: 2026-08-07
---
# Desktop-app rendering defaults — eager, sync, stable, immutable

## Context and Problem Statement

Media Centaur is a single-user desktop application with a library bounded by local disk, but it had inherited every "good web citizen" default (lazy images, async decode, unkeyed iterators, entrance animations, an eager progress bar, a longpoll fallback, revalidated bundles), and each one shows up as perceived latency on local navigation.

## Decision Outcome

Memory and bandwidth are free here; trade them for instant perception.

1. **Eager + sync decode** on every in-flow `<img>`: `loading="eager" decoding="sync"`. `loading="lazy"` only on bounded reveal-on-demand surfaces (cast headshots, modal search results). Enforced by MC0016.
2. **`fetchpriority="high"`** on the modal backdrop only, so the signal stays meaningful.
3. **Stable `id={...}` on every `:for` iterator root**, pattern `"<component>-<entity_id>"`, so morphdom preserves items across patches.
4. **No entrance animations on routine renders.** Modal panel transitions stay, at 150 ms.
5. **`topbar.show(800)`**: the progress bar appears only for genuinely slow operations.
6. **WebSocket-only transport**, no longpoll fallback.
7. **Hashed assets are `immutable`**: `Plug.Static` sends `public, max-age=31536000, immutable` for versioned requests.
8. **Versioned image URLs are `immutable`; plain image URLs are `max-age=3600` + ETag** (`MediaCentaurWeb.Plugs.ImageServer`).
9. **A static `data-input` on `<html>`** so input-gated CSS matches on first paint. The default is `keyboard` (amended 2026-08-07: it started as `mouse`, which hid the focus ring at load on a remote-driven appliance); a real pointer switches it on first movement.

[UIDR-032](2026-09-06-032-page-hero-backdrops-paint-from-a-decoded-bitmap-cache.md) carves out the Home hero backdrop, which paints from a decoded-bitmap canvas instead of an `<img>`.

| Value | Lives in |
|---|---|
| eager + sync on in-flow `<img>` | Credo MC0016 |
| stable iterator ids, no entrance animations | `user-interface` skill |
| `topbar.show(800)` | `assets/js/app.js` |
| transport, immutable hashed assets | `endpoint.ex` |
| image cache headers | `plugs/image_server.ex` |
| static `data-input` | `layouts/root.html.heex` |

### Consequences

* Grids eager-load every visible card and `decoding="sync"` blocks the main thread for the decode; both are cheap at desktop-library sizes with cached bytes.
