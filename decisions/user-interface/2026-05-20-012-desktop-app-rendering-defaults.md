---
status: accepted
date: 2026-05-20
---
# Desktop-app rendering defaults — eager, sync, stable, immutable

## Context and Problem Statement

Media Centaur is a specialized desktop application: single user, runs
locally, has a curated library bounded by what's on disk. It is not a
public-internet web app serving anonymous traffic over a hostile
network. But the codebase had inherited every "good web citizen"
default that those constraints justify, and each one shows up as
perceived latency on local navigation:

- `<img loading="lazy">` on every poster, backdrop, and tile — the
  browser must wait on intersection-observer before fetching, even
  when the image is already in the disk cache.
- Default `decoding="auto"` means the browser typically decodes
  off-thread and paints a blank frame first.
- `:for` iterator roots without stable `id={}` — morphdom can't
  match them across re-renders and recreates each element on patch,
  re-triggering the decode/paint cycle.
- `phx-mounted={JS.transition(...)}` entrance animations on the
  library card replay on every navigation back into the page.
- `topbar.show(300)` flashes the progress bar on navigations that
  complete in 100-300ms — adding perceived latency to operations
  that would otherwise feel instant.
- LiveView transport configured with a longpoll fallback —
  transport degradations hide as "the app just feels slow" rather
  than surfacing as a normal reconnect.
- `Plug.Static` served hashed JS/CSS bundles without an explicit
  `immutable` cache directive, so the browser revalidates each
  bundle on every reload even though Phoenix's content-hashed
  filenames make them genuinely immutable.
- `<html>` rendered with no `data-input` attribute, so CSS gated
  on input-method (focus-ring suppression for mouse) didn't match
  until JS ran and set the attribute — producing a brief stale
  focus-ring flash on initial paint.

Each of these was the right call for some other app. None of them
is right for this one.

## Decision Outcome

Chosen option: adopt a coherent set of "specialized desktop app"
rendering defaults, trading memory and bandwidth (essentially free
in this context) for instant perception. Capture the rule in code
where possible, in the skill and this ADR otherwise.

The defaults:

1. **Eager + sync-decode for in-flow images.** Every `<img>` in a
   component rendered above the fold or in a horizontal row uses
   `loading="eager" decoding="sync"`. `loading="lazy"` is reserved
   for bounded reveal-on-demand surfaces (cast headshots inside
   the "More Info" pane; track-search results inside a modal) and
   flagged elsewhere by `MediaCentaur.Credo.Checks.ImgAttributeDefaults`
   (MC0016).

2. **`fetchpriority="high"` on the page backdrop and modal
   backdrop.** Two genuinely dominant images per surface.
   Not blanket — the priority signal must remain meaningful.

3. **Stable `id={...}` on every `:for` iterator root.** Without
   it, morphdom recreates each item on every re-render. The
   id pattern is `"<component>-<entity_id>"` (e.g.
   `"poster-row-#{item.entity_id}"`).

4. **No entrance animations on routine renders.** A page paint is
   not a moment to celebrate. `phx-mounted={JS.transition(...)}`
   for fade-in / translate-in is removed. Modal panel transitions
   stay (they signal layering) but are tightened to 150ms.

5. **`topbar.show(800)`** — the progress bar shows only for
   genuinely slow operations. Local LV navs complete well under
   this threshold and stay bar-less.

6. **WebSocket-only transport.** No longpoll fallback. A real
   reconnect attempt is better UX than a hidden slow path.

7. **Hashed assets are `immutable`.** `Plug.Static` is configured
   with `cache_control_for_vsn_requests: "public, max-age=31536000,
   immutable"`. Phoenix's content-hash URL scheme guarantees the
   safety of this directive.

8. **Versioned image URLs are `immutable`; plain image URLs are
   `max-age=3600` + ETag.** Implemented in
   `MediaCentaurWeb.Plugs.ImageServer`. The version parameter
   (`?v=<n>`) acts as the cache key.

9. **Sane static defaults in HTML to avoid pre-JS flash.**
   `<html data-input="mouse">` is the static default; JS upgrades
   it once input-method detection runs. Any CSS gated on
   `[data-input=...]` matches immediately on first paint.

### Consequences

* Good, because every navigation paints with its images already
  drawn — no blank frame, no decode flicker, no entrance animation
  replay.
* Good, because morphdom preserves iterator items across patches,
  so unrelated re-renders don't recycle the entire row.
* Good, because the cache configuration is explicit and the
  trade-offs are documented at the call site.
* Good, because the rule about `loading="lazy"` is enforced by a
  Credo check at precommit, so the next contributor doesn't have
  to re-discover this decision.
* Bad, because library grids with many cards eager-load every
  visible card on page entry — accepted because the bounded
  desktop-library size makes this cheap.
* Bad, because `decoding="sync"` does block the main thread for
  the decode — but the alternative is the blank-frame flash we're
  paying to remove, and for cached bytes the cost is sub-frame.
* Bad, because users on the previous client (which still tried
  longpoll fallback) need a hard reload after the disabling
  release to clear the cached client — one-time cost.

## Where each value lives

| Value | Enforced by | Source |
|---|---|---|
| `loading="eager" decoding="sync"` on in-flow `<img>` | Credo check (`MC0016`) | `credo_checks/img_attribute_defaults.ex` |
| Stable `id={...}` on iterator roots | Convention | `user-interface` skill |
| No entrance animations on mount | Convention | `user-interface` skill |
| `topbar.show(800)` | Code | `assets/js/app.js` |
| WS-only transport | Code | `lib/media_centaur_web/endpoint.ex` |
| Immutable hashed assets | Code | `lib/media_centaur_web/endpoint.ex` (`Plug.Static` opts) |
| Image cache headers (versioned vs. plain) | Code | `lib/media_centaur_web/plugs/image_server.ex` |
| Static `data-input="mouse"` default | Code | `lib/media_centaur_web/components/layouts/root.html.heex` |
