# Downloads page — command-center layout

**Date:** 2026-06-10
**Status:** approved (brainstorm session with Shawn; option A of three compositions, collapse story validated visually)

## Problem

The Downloads page (`/download`, `MediaCentaurWeb.AcquisitionLive`) was designed as a single `max-w-4xl` column. On a 4K display the page left-stacks into a corner, and because it did not pass `full_width` to `Layouts.app`, the `.page-atmosphere` backdrop band clipped hard at the `max-w-7xl` container edge — a visible rectangular artifact mid-screen. Home and Library are full-bleed and fluid; Downloads was the outlier.

A baseline fix already sits in the working tree (uncommitted, this session): `full_width`, per-zone width caps, and multi-column card grids at `2xl`/`min-[2200px]`. This design supersedes parts of that baseline (noted below) with a deliberate wide-screen composition instead of "same stack, wider".

## Decision

**Command center:** at wide widths the page splits into a **main column** (the "now": search, drafts, active pursuits) and a **ledger rail** (the "record": history, other downloads). On laptops the page is exactly today's single capped column. One DOM; CSS-only breakpoints; no new assigns, events, or queries.

Rejected alternatives: lifecycle board (state columns — fragile when 0–1 items downloading), hero strip (downloads-lead band — deferred; composes with this design later as a richer treatment *inside* the active zone).

## Layout by breakpoint

| Width | Composition |
|---|---|
| `< 2xl` (≲1536px) | Today's stack, zones capped `max-w-4xl`: omnibox → search results → drafts → notice → active → history (collapsible, default closed) → other downloads. |
| `≥ 2xl` | Two-region grid: main `minmax(0,1fr)`, rail `minmax(360px,460px)` (tune the upper bound visually), `gap-x-8`. Main collection zones (drafts, active pursuits) release their `max-w-4xl` cap; the omnibox and release-search results keep `max-w-4xl` inside main. |
| `≥ min-[2200px]` | Same regions; the active-pursuits grid inside main goes 2-up. |

## Zone assignment

- **Full width, above both regions:** header (title, pursuit summary, watching-link).
- **Main:** `MediaOmnibox`, `Search.search_zone` (release results), draft plans, download-client notice, Active pursuits (full cards + grouped compact rows).
- **Rail:** History (filter chips + search input + rows), Other downloads (orphan queue).

DOM order of the two wrapper divs (main first, rail second) reproduces today's stack order below `2xl` — no reordering, no `display: contents` tricks needed.

## History disclosure semantics

- **Rail widths (`≥ 2xl`):** history is the rail's content — always visible. Static "History" heading; the chevron disclosure is hidden.
- **Stack widths:** today's behavior unchanged — chevron toggle, collapsed by default, auto-expands on history deep-links (`?filter=`/`?search=`).
- Implemented with responsive classes only (`hidden 2xl:block` family). `history_open?` keeps its meaning at stack widths and is ignored visually at rail widths. History rows are already loaded eagerly on mount, so no data-loading change.

## Supersessions of the uncommitted baseline

- History rows: revert `2xl:grid-cols-2 min-[2200px]:grid-cols-3` → single column (they live in a narrow rail now).
- Active pursuits grid: `2xl:grid-cols-2 min-[2200px]:grid-cols-3` → `min-[2200px]:grid-cols-2` (main column is narrower than full bleed).
- Orphan zone: drop its `2xl:max-w-6xl` (the rail constrains it).
- Kept from baseline: `full_width`, atmosphere fix, `max-w-4xl` caps on command surfaces and notices/empty states.

## Input-system nav graph

`assets/js/input/config.js` → `navGraph.download` currently references zones that don't exist on the page (`sections`, `grid`). Rewrite to the real zones (`drafts`, `pursuits`, `history`, `other_downloads`, plus the omnibox/search zones as rendered) with left/right edges between main and rail and sidebar leftmost. Update `cursorStartPriority.download` to match. The page carries the input-system WIP notice, so this closes drift rather than adding scope.

## Testing

- No new domain logic → no new unit tests. Existing `/download` smoke + `acquisition_live_test.exs` cover render paths.
- New render branch (history rows present while `history_open? == false`): exercised by the existing smoke fixture, which seeds history rows.
- E2E download spec does not exist (page is nav-WIP); not added here.

## Verification

Run `mix precommit`. Final visual check is Shawn's, on his 4K display and a smaller window — do **not** boot showcase/dev instances for screenshots without asking.

## Out of scope (future)

- Artwork-rich pursuit cards (poster/backdrop treatment inside the active zone — the "hero strip" composition folded in).
- Watching-summary card in the rail (stays a header link).
- E2E nav coverage for the download page behavior.
