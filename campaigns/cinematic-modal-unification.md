# Cinematic Modal Unification

**Status:** Phase 1 in progress (started 2026-08-11)
**End state:** Every modal grounded in a TMDB identity renders the same cinematic
shell (pinned orientation block over a fixed backdrop), fed by a single artwork
contract with a promotion ladder from hotlink → temporary local → permanent library.

## Core idea

A TMDB identity is a first-class presentable subject: every modal grounded in one
renders the same cinematic shell — the only differences between a library title and
a merely-known title are where the data comes from and how long the artwork is
retained.

## Approved design (2026-08-11, with Shawn)

### The cinematic frame

The pinned-block system currently welded into `ModalShell` + `DetailPanel`
(`.modal-panel--full`, panel-fixed `.modal-page-backdrop` + `.modal-page-atmosphere`,
`#detail-scrollport` with the scroll-timeline, sticky `.detail-orientation` with its
`.orientation-backing*` replica, `DetailScrollGeometry`/`DetailBodyScroll` hooks)
is extracted into one tenant-agnostic component with `:orientation` and `:body`
slots. The frame renders **both** backdrop copies itself, making the
byte-identical-URL invariant structural instead of conventional (today it is
duplicated across `modal_shell.ex` and `detail_panel.ex`).

Tenants: library DetailPanel (tenant #1, behavior unchanged), plan modal, Incoming
title modal. Each tenant declares its own nav overlay/zones — context names are
never reused across surfaces (UIDR-019 lesson).

### The artwork promotion ladder

| Tier | Condition | Source | Lifetime |
|---|---|---|---|
| Browsing | No durable reference (search rows, plan modal, cast headshots everywhere) | TMDB CDN hotlink via one shared URL helper | None — nothing downloaded |
| Referenced | Tracked item or non-terminal pursuit exists for the `(tmdb_type, tmdb_id)` | `TmdbArtwork` local cache, ensured when the reference is created | Swept when **7 days since last use AND no hold** |
| Library | Entity imported | Entity-keyed permanent store (unchanged) | Forever |

Cleanup semantics (Shawn's requirement): temporary assets are deleted only when the
TTL has elapsed **and** nothing references the identity anymore. Pursuits reference
TMDB identities (not releases), so the hold key equals the cache key.

`TmdbArtwork` is the generalization of `ReleaseTracking.ImageStore` +
`Acquisition.Artwork`: layout `{data_dir}/images/tmdb/{type}-{id}/{role}.{ext}`,
downloads through the `ImageFiles` facade with the pipeline's role sizing (no more
raw originals), served by the existing `/media-images/*` plug + `?w=` derivative
ladder. Hold providers are config-registered (mirroring
`:retention_policy_providers`): ReleaseTracking contributes tracked-item ids,
Acquisition contributes non-terminal pursuit ids. The sweep rides the daily
`Retention.SweepJob`, **replaces** the `:tracking_artwork` policy (orphan rule
becomes the degenerate case "tracked item = hold"), and purges derivatives of
removed masters.

### Explicit decisions

- Hotlinks are sanctioned for browsing-tier surfaces and cast headshots — this
  supersedes UIDR-014 §4's "no hotlinking" (already violated by shipped code);
  a new decision record lands in Phase 5.
- TTL is a 7-day constant, not a setting.
- Pursuit modal (imageless today) and Review page (inline panel, not a modal) are
  **out of scope** this campaign; Review adopts the shared CDN helper in Phase 5
  but keeps its layout.
- Search-result list thumbs stay hotlinked; downloading artwork for scrolled-past
  rows is churn.

## Phases

1. **Extract `cinematic_shell`** from ModalShell/DetailPanel; DetailPanel becomes
   tenant #1. Stories per MC0009; `test/e2e/detail-backdrop.spec.js` stays green;
   preflight `scroll-state(stuck` assertion still applies.
2. **`TmdbArtwork` cache** promotion + hold-based retention + idempotent disk
   migration from `images/tracking/`.
3. **Plan modal** re-seats on the frame (hotlinked imagery, logo lockup from the
   TMDB detail `images` ride-along).
4. **Title modal** re-seats on the frame (local tracking artwork).
5. **Ship:** decision records (UIDR superseding 014 §4; ADR for TmdbArtwork
   retention), shared `tmdb_cdn_url` helper adopted everywhere incl. Review,
   delete dead `title_result_summary.ex`, retire stale
   `campaigns/unified-title-search.md`, fix `.claude/skills/user-interface`
   inventory (still lists `track_modal/1`), reconcile `specs/IMAGE-CACHING.md`
   drift (`source_url`, partial-downloads claim), wiki + CHANGELOG.

## Known traps (from exploration)

- Tailwind/Lightning CSS minifier once dropped `@container scroll-state(stuck: top)`
  — tailwind pinned to 4.3.3; `scripts/preflight` greps minified CSS for it.
- `DetailScrollGeometry` re-asserts inline custom props in `updated()` because
  morphdom wipes inline style on every patch.
- `:full_bleed` URLs must stay byte-identical to the panel backdrop URL or the
  orientation replica and ArtworkWarmup both break (`live_helpers.ex` docstring).
- `mc-ui-probe align|shift|shot` verifies backdrop geometry after touching
  `.orientation-backing*` / modal backdrop CSS.
- Binary image fetches do not pass the TMDB rate limiter (metadata calls do).

## Decisions log

- 2026-08-11: design approved (tiers, 7d TTL, tenant scope = plan + title modals).

## Next steps

- Phase 1 implementation.
