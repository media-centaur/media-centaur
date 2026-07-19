---
status: planning
started: 2026-07-19
last_updated: 2026-07-19
---
# Complexity retirement

## Goal

A read-only engineering review (2026-07-19) of the ~100k-LOC tree found the
architecture sound but carrying a small, concentrated set of avoidable
complexity: stored-yet-derivable state kept fresh by sweeps, duplicated
representations of one concept, dead code whose docstrings oversell it, and one
place where an existing abstraction is bypassed and silently breaks a shipped
feature. This campaign retires those items — deleting or collapsing each toward
the design the rest of the codebase already implies — without regressing
behavior. It is a deliberate elegance pass, not a bug-bash: each item names what
gets deleted and how behavior is preserved.

## Status

In progress. Wave 1 started 2026-07-19.

Findings verified at cited call sites during review; line numbers may have
drifted — reconcile against `git log` before each item.

**W1-1 reconciliation (2026-07-19):** the original diagnosis was incomplete.
It attributed the usenet-only wizard block to `IntegrationHealth`'s
`configured?` axis, but `Setup.Gate.check(:download_client, …)` does **not**
read health for that step (`:download_client` is not in `@gating_test_steps`) —
it reads the **probe**. The actual wizard blocker is
`setup_live.ex` `probe_input/0` + `setup_live/probes.ex` `download_client/1`,
which gate on `download_client_password_configured?` (the *torrent* password).
A SABnzbd-only install has no torrent password → probe `:not_configured` →
step blocked despite a configured, working client. W1-1 therefore fixes **three**
sites, unified by one idea — *"is a download client configured?"* =
`Downloads.configured_clients() != []`, not *"is the torrent password set?"*:
`Verifier.run(:download_client)` (route via `Dispatcher.drivers()`),
`IntegrationHealth` (`configured_for?` + `integration_for_key` widen to the
two-slot key set via a new `Downloads.config_key?/1` seam), and the SetupLive
probe (the real unblock).

## Decisions made

Append-only log. Each entry: date, one-line decision, link to ADR / commit.

* `2026-07-19` — Campaign opened from the complexity review. Scope frozen to the
  10 review findings + 5 greenfield notes; no new capability, only deletion /
  collapse. Ordered by payoff ÷ risk, grouped by area to minimize context
  switching.
* `2026-07-19` — Test policy per item: behavior-fixing items (W1-1, W3-1) are
  **red-first** (write the failing test, then fix) per the testing skill;
  dead-code deletions remove their orphaned tests in the same commit; collapses
  rely on existing coverage and add a test only where a contract narrows.
* `2026-07-19` — W1-1 scope corrected during reconciliation (see Status): the
  usenet-only wizard block lives in the SetupLive **probe**, not `Setup.Gate`'s
  health check. Fix widened to three sites over one seam
  (`Downloads.config_key?/1` + `configured_clients/0`). No new capability — still
  a collapse of one duplicated concept ("download client configured?").

## Next steps

Work top-down. Each item is independently shippable; commit per item
(`fix:` / `refactor:` / `chore:`) so nothing bundles. Front-loaded by
payoff ÷ risk.

### Wave 1 — high payoff, low risk (behavior fixes + dead ceremony)

1. **✅ DONE (2026-07-19).** **IntegrationHealth: route through the two-slot
   `Dispatcher` seam.** Shipped across three sites (see Status reconciliation):
   `Verifier.run(:download_client)` now folds over `Dispatcher.drivers()`;
   `IntegrationHealth.configured_for?(:download_client)` derives from
   `Downloads.configured_clients/0` and reacts to any slot key via the new
   `Downloads.config_key?/1`; the SetupLive probe gates on
   `download_client_configured?` (any slot) instead of the torrent password.
   Red-first tests: verifier `:not_configured` routing, IntegrationHealth
   usenet-only `configured? == true`, probe ok-when-any-client. Full suite green.
   *Original scope below (kept for the record):*
   *Files:* `lib/media_centaur/integration_health.ex` (`@config_key`),
   `lib/media_centaur/integration_health/verifier.ex` (`run(:download_client)`).
   `Verifier` hardcodes `QBittorrent.test_connection()` and `@config_key`
   hardwires `download_client: :download_client_password` — a SABnzbd-only
   install probes an unconfigured qBittorrent (always errors) and its
   `configured?` axis is permanently false, blocking `Setup.Gate`. Route
   `run(:download_client)` through `Downloads.Dispatcher.driver_for/1` (the seam
   `acquisition.ex:606` already uses) and base `configured?` on the configured
   client, not one torrent key. **Red-first**: failing test for a usenet-only
   config clearing the wizard. qBittorrent-only prod path is unchanged
   (`driver_for(:torrent) → QBittorrent`).

2. **✅ DONE (2026-07-19, commit fb1773b6).** **Import pipeline: delete the dead
   batcher.** Removed `batchers:` + the identity `handle_batch/3` from
   `import.ex`; messages now ack right after `handle_message` (no 5 s batch
   latency). Completion broadcast still fires inline in `handle_complete/1`.
   Fixed the stale moduledoc + `docs/pipeline.md` lines. Discovery's and Image's
   batchers left intact. Pure dead-code deletion — no test exercised the batcher
   (`pipeline_test.exs` drives `process_payload/1` directly), so no orphaned
   tests. Precommit green. *(Note: found `credo --strict` pre-existing-red since
   151daa35 — an unrelated `LongQuoteBlocks` overshoot in `console_live/shared.ex`
   — fixed first in its own commit 0bdff879 to unblock the campaign.)*

3. **✅ DONE (2026-07-19, commit d101faee).** **Library: delete the test-only
   dead-function cluster.** Removed `FilePresence.list_stale/1`,
   `ExternalIds.find_owner/2` (+ orphaned `schema_for/1` + `owner_type` type),
   `EpisodeList.index_progress_by_episode/1` and
   `MovieList.index_progress_by_movie/1` (+ each module's now-orphaned
   `progress_loaded?/1`). Demoted `Progress.lookup_in_memory/1` to `defp` (sole
   caller `overlay_in_memory/1`). Fixed the FilePresence moduledoc (cited
   `list_stale` → now names AbsenceSweeper's `last_seen_at` sweep) and the
   `movie_list_test` describe mislabeled `index_progress_by_movie` (it exercises
   the live `index_progress_by_key`). Orphaned tests removed same commit
   (5423→5408). Precommit green.

4. **✅ DONE (2026-07-19, commit d9f169e0).** **Library view projections: delete
   the redundant `:ordered_set` sorts.** Dropped the `Enum.sort_by(fn {rank,_}
   -> rank end)` from `continue_watching`, `recently_added`, `hero_candidates` —
   `:ordered_set` iterates in unique-key order, so `tab2list` is already
   rank-sorted (behavior-preserving; matches `browse.ex`'s documented pattern,
   which we copied as the explanatory comment). Existing 184 view tests green.
   (Extraction of the shared skeleton is W4-1.)

**Wave 1 complete (2026-07-19).** All four items shipped as individual commits
(583343e4, fb1773b6, d101faee, d9f169e0), unpushed. Pre-existing `credo --strict`
red (LongQuoteBlocks in `console_live/shared.ex`, from 151daa35) cleared in
0bdff879 to unblock the campaign's precommit gate.

### Wave 2 — duplicated representations (low-medium risk collapses)

**Wave 2 complete (2026-07-19).** Commits eaf23178, ce0b73e5, c00bb82e — unpushed.

1. **✅ DONE (eaf23178).** **Own the `/media-images/…` web path in
   `Library.Image.web_path/1`.** Added the nil-tolerant single builder (owns
   `@web_prefix`); routed ~11 construction sites (Library, ReleaseTracking,
   Acquisition, web incl. `live_helpers.image_url/2` + the two `sized_image_url`
   concat sites) through it. Boundary-clean (Image exported; every caller
   context already deps on Library). Output byte-identical for real inputs;
   `sized_image_url`'s `"/media-images/" <> _` match head left as the consumer
   side of the contract.

2. **✅ DONE (ce0b73e5).** **Consolidate the two ISO 639 tables into
   `MediaCentaur.Iso639`.** New boundary-neutral owner (`top_level?` escape
   hatch) exposes `normalize/1` (→3-letter) + new `to_iso1/1` (→2-letter);
   `Playback.Iso639` is a thin `defdelegate` facade (ADR-048 API + export + all
   callers unchanged), `Subtitles.LanguageCode` projects via `to_iso1/1`.
   Subtitle detection widened to the fuller set (intended; tests added for the
   newly-recognised langs est/hrv/isl/srp/slk).

3. **✅ DONE (c00bb82e).** **Delete speculative `BrowseItem.present?` +
   `:present_only`.** Field was hardcoded `true`, filter a tautology, option a
   no-op. Removed field/filter/option + doc/story/test refs; the real
   "fileless entity excluded" coverage re-pointed at plain `Views.browse()`.
   Kept Search's genuinely-real `present_only` (presence-agnostic source).

### Wave 3 — derivable state (medium risk, deletes a bug class)

1. **Derive `Release.released` from `air_date`; delete the sweep.**
   *Files:* `release_tracking/release.ex`, `release_tracking.ex`
   (`mark_past_releases_as_released/0`), `helpers.ex` (creation-time stamping).
   `released` is exactly `air_date != nil and air_date <= today`, materialized and
   re-freshened by a midnight sweep — the stale-across-midnight class behind past
   "Season announced" phantoms. Drop the column + stamping + sweep + its 2 calls;
   replace ~19 read sites with an `air_date <= today` comparison (`fragment` at
   query sites; `Date.compare` in the pure modules that already receive `today`).
   Append-only drop migration (ADR-027 / safe-migration policy). **Red-first**
   for the midnight-boundary case.

### Wave 4 — structural elegance (higher effort, high payoff)

1. **Extract `Library.Views.RankedProjection`.**
   `continue_watching` / `recently_added` / `hero_candidates` / `browse` share an
   identical `subscribe / relevant? / refresh_cache / read / read_from_ets /
   read_from_db / to_view_model / ensure_table` skeleton (`cache.ex`'s behaviour
   doc already names them as one flavour). Collapse to
   `use Library.Views.RankedProjection` parameterized by
   `{table, source_fun, item_mapper, default_limit, view_tag, extra_topics}`. Do
   this *after* W1-4 so the sorts are already gone. External `read/refresh_cache`
   contract unchanged; existing view tests cover it.

2. **Collapse the two acquisition `Recipe` structs.**
   `view_models/recipe.ex` + `pursuits.ex` `build_recipe/1` duplicate the
   canonical `pursuits/recipe.ex` (`build_recipe/1` hand-copies the discrimination
   `Pursuits.Recipe.from/1` already does, two lines above a call to it). Embed
   `Pursuits.Recipe` in `PursuitHeader` + a `search_queries` field;
   `build_recipe/1 → PursuitRecipe.from(p)`. Single consumer (detail header).
   Crosses the ADR-039 "components consume ViewModels" line — decide explicitly
   whether the header owns a thin VM wrapping `Pursuits.Recipe` or embeds it
   directly; either way one representation, not two.

3. **Split `activity_widget_components.ex` (1152 LOC, 8 subsystems).**
   Split into `components/status_widgets/<subsystem>.ex`, mirroring
   `components/detail/more_info/*`; move the 8 stories alongside. Pure `:html`
   components, story-covered — mechanical. Removes the layer's highest-churn
   merge-conflict hotspot. (Lowest priority — hygiene, no behavior at stake.)

### Wave 5 — greenfield notes (fold in opportunistically, don't gate the campaign)

1. Fix the `library:progress` docstrings (`progress/events.ex`, `progress.ex`,
   `topics.ex`) that call it a "live UX hook" — it has zero prod subscribers; per
   ADR-041 it is a deterministic **test** hook. Correct the prose; keep the module.
2. Rename `StatusHelpers.format_bytes` → `format_bytes_iec` and signpost that
   media sizes use `Format.format_size_decimal` (SI). Deliberate split, just
   unsignposted.
3. Extract one "parse stored ISO8601 datetime, default on garbage" helper for the
   ~6 Settings accessors that re-implement it (`self_update/health.ex`,
   `storage.ex`, `history.ex`, `capabilities.ex`, `update_checker.ex`, …) —
   preserve each call site's fallback polarity.
4. `detail.ex`: compute `top_level_container(type, display)` once in `build_item`
   instead of via ~20 `container_X` wrappers that each recompute it per row (keep
   `container_director`/`container_year` — real logic).
5. `Search.SearchProvider` single-impl behaviour — **keep** unless a second
   provider is abandoned; the `@callback` gives cheap `@impl` checking. Logged so
   it isn't re-flagged.

## Completion criteria

* Waves 1-4 items all merged, each as its own commit; `mix precommit` green.
* No stored boolean remains that is a pure function of `air_date` (W3-1 gone).
* Exactly one owner each for: the web image-path prefix, the ISO 639 code table,
  the pursuit search-recipe struct, the ranked-projection skeleton.
* No `lib/` function survives that is reachable only from its own test (W1-3).
* Every docstring corrected in W1-3 / W5-1 describes the actual live path.
* Wave 5 items either done or explicitly logged as "keep, by design."
* File removed on completion (ADR-042 — git history is the archive).

## Pointers

* Review source: complexity review, 2026-07-19 session (six parallel context
  surveys, adversarially verified).
* ADRs: [039](../decisions/architecture/2026-05-07-039-acquisition-pursuits.md)
  (ViewModel boundary), [041](../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md)
  (projections / progress test hooks), [048](../decisions/architecture/2026-05-22-048-canonical-language-codes-at-boundary.md)
  (single ISO 639 table), [052](../decisions/architecture/2026-05-31-052-download-stack-control-plane.md)
  / [054](../decisions/architecture/2026-06-08-054-external-dependency-faults-are-subsystem-health.md)
  (download slots / subsystem health), [056](../decisions/architecture/2026-06-10-056-release-tracking-wants.md)
  (release-tracking wants), [027](../decisions/architecture/2026-03-07-027-regression-tests-append-only.md)
  (append-only migrations/tests).
* Key modules: `integration_health/verifier.ex`, `pipeline/import.ex`,
  `library/views/*`, `library/file_presence.ex`, `release_tracking/release.ex`,
  `acquisition/view_models/recipe.ex`, `subtitles/language_code.ex`,
  `playback/iso639.ex`, `components/activity_widget_components.ex`.
