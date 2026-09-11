# Tracking is a person's act — design

**Date:** 2026-09-07
**Campaign:** `campaigns/tracking-is-a-persons-act.md` (completed and removed — see git history)
**Supersedes in part:** [ADR-065](../../../decisions/architecture/2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md) §2, §4, §5, and the collection carve-out; [UIDR-035](../../../decisions/user-interface/2026-09-07-035-two-title-surfaces.md)'s "`Remove from watchlist` becomes the separate, unrelated act".

## Glossary

| Term | Meaning |
|---|---|
| **title intent** | `Discovery.TitleIntent` — the person's standing intent about one title, keyed `{tmdb_id, media_type}`. The only authored record in this design. |
| **rung** | Where that intent sits: `:list`, `:follow`, `:ask`, `:grab`, `:default`. Off is the absence of the record, not a stored value. |
| **tracked title** | `ReleaseTracking.Item` — machinery derived from a rung of `:follow` or above. Holds the calendar, the wants and the library link. Authored by nobody. |
| **download params** | Per-title acquisition settings — quality floor and ceiling, 4K patience, season-pack preference. Acquisition's, not release tracking's. |
| **scope** | What one click downloads: first season, or all aired. |

Words deliberately *not* used as rung names: **plan** (it is `Acquisition.Plans.Plan`, the draft the Ask rung parks) and **track** (it is the machinery, and every rung above Follow tracks too).

## Core idea

> A person holds one standing intent per title, on a ladder; every tracked title, calendar row, want and plan is machinery derived from where that intent sits.

Both campaign decisions follow from it rather than sitting beside it. "Tracking is a person's act" is *the intent is authored, and nothing else writes it*. "Off deletes" is *machinery below the rung does not exist*.

## The ladder

```
Off        not on your list                            (no record)
List       on your list; nothing else                  :list
Follow     its releases appear under Coming up         :follow
Ask        parks a draft plan when a release drops     :ask
Grab       downloads it                                :grab
Default    follows your global auto-grab setting       :default
```

`:default` resolves against the global auto-grab setting live, and only while the rung has never been set to a concrete value — unchanged from ADR-065 §3.

## Data model

### `Discovery.TitleIntent` — authored

Table `title_intents` (renamed from `watchlist_items`).

```elixir
field :tmdb_id, :integer
field :media_type, Ecto.Enum, values: [:movie, :tv_series]
embeds_one :title, MediaCentaur.TMDB.Title
field :rung, Ecto.Enum, values: [:list, :follow, :ask, :grab, :default]
field :source, Ecto.Enum, values: [:manual, :friend], default: :manual
field :note, :string
field :activity_id, Ecto.UUID
```

Identity, provenance and the provenance-pairing validation carry over unchanged from `WatchlistItem`. The one addition is `rung`.

`TitleIntent` owns the rung ordering (`rung_at_least?/2`) and the grab mapping that `Item.grab_mode/2` holds today:

```
:default        → the global default
:grab           → "all_releases"
:ask            → "ask"
:list, :follow  → "off"
```

### `ReleaseTracking.Item` — derived

Loses `tracking_mode`, `min_quality`, `max_quality`, `quality_4k_patience_hours`, `prefer_season_packs`. What remains is machinery: the library link, `last_refreshed_at`, `last_library_season/episode`, `dismiss_released_before`, and the ids the drop planner verifies grabs against (`imdb_id`, `tvdb_id`, `original_title`, `origin_country`).

`Item.name` stays. It looks like a duplicate of `intent.title.name`, but dropping it buys a join at every read site and `Event.item_name` denormalises it deliberately (migration `20260513083409`). Left alone on purpose.

### Per-title download params — Acquisition's

New Acquisition-owned record keyed `{tmdb_id, media_type}`, carrying one `embeds_one :params` so a new preference is a struct field rather than a migration. Absent record, or absent key, means the global default.

This is what makes "Accept lower quality" stop creating a tracked title: the preference had no home but `ReleaseTracking.Item`, so the act had to manufacture one.

## Derivation

A `ReleaseTracking.Item` exists **iff**:

```
rung_at_least?(rung, :follow)  and  not (media_type == :movie and the film is in the library)
```

The second clause is the completion rule: a single film you own has no future release, whatever the rung says. The rung is *not* lowered when a film lands — the system never moves a person's intent — so the control shows the rung with a line saying you own it.

There is no collection case. Collections were only ever created by `Scanner`, which has no caller in `lib/`; deleting it deletes ADR-065's collection carve-out with it.

`Reasons.retain?/1` disappears as arbitration. What survives is this one rule, at the one place that derives.

## The one write path

`ReleaseTracking.set_rung(title, rung, attrs \\ %{})`:

1. Upsert the `TitleIntent` at `rung` (or delete it, for Off).
2. If the rung is at or above `:follow` and no machinery exists — fetch TMDB, create the item, releases, wants, artwork.
3. If it is below `:follow` and machinery exists — delete the item, its releases and its wants.
4. Broadcast.

`set_rung_async/3` keeps the TMDB fetch off the LiveView, as `arm_async/2` does today.

It lives in `ReleaseTracking` because that is the context that can see both sides — ADR-065 §6's argument, unchanged. `Discovery.TitleIntents` exposes the pure write (`upsert_rung/3`, `delete/2`) that it calls.

`Acquisition` gains `MediaCentaur.Discovery` in its `Boundary` deps: the drop planner acts on the person's intent, so it reads it. Direction stays one-way; Discovery still depends on nothing downstream.

### What this removes

There is no invariant to enforce, because "a tracked title that is not on the list" is unrepresentable. So:

- `ReleaseTracking.Reasons` — deleted.
- `ReleaseTracking.WatchlistListener` — deleted. Nothing to reconcile.
- `ReleaseTracking.arm/2`, `arm_async/2`, `disarm/1` — replaced by `set_rung/3`.
- `Discovery.add_to_watchlist/2`, `remove_from_watchlist/2` — replaced by `set_rung/3` at `:list` and Off.
- `ReleaseTracking.reconcile/2` keeps only the completion rule.

## Surfaces

### One control

`TrackingModeControl` becomes the intent control: six buttons, `Off · List · Follow · Ask · Grab · Default`, with the selected rung's one-line consequence beneath. The separate watchlist Add / Remove control in the title detail modal is deleted, and with it the `title_watchlist_add` / `title_watchlist_remove` events and the "choosing a mode adds it to your watchlist" disclosure — there is nothing left to disclose when the ladder is one control.

`WatchlistAware` becomes `IntentAware`, carrying `ref => rung` instead of a `MapSet` of refs, so a list row can show its rung.

### The acts that raise a rung

| Surface | Today | After |
|---|---|---|
| Download menu | *Download* (first season), *Download all* — which silently starts tracking | *Download first season*, *Download all*, ***Download all and track*** — only the third sets a rung |
| Plan modal checkbox | "Also grab future episodes" → seeds `:watch` → **never grabs** | sets `:grab`, which is what the checkbox says |
| Gap banner | "Track these later" → seeds `:watch` → the drop planner skips the item, so the "will keep looking" flash is false | raises to at least `:follow`, and the flash states what the current rung actually does |
| Library import | `AutoTrackJob` starts following every active series | nothing |
| "Accept lower quality" | creates a tracked title to have somewhere to write | writes download params; follows nothing |

The two middle rows are live bugs, not just honesty problems: `Item.grab_mode(:watch, _)` returns `"off"` and `DropPlanner.plan_item/4` bails on `"off"`, so a title at Follow never searches and never grabs.

### Library import replaces with nothing

New series sit in the library untracked. Coming up shows only what a person put there. No prompt, no suggestion list.

### Deleting a series from the library no longer stops tracking it

`LibraryLinks.refresh_for/1:88` currently deletes the tracked title outright when its container is gone, bypassing `Reasons` entirely — a live contradiction of ADR-065. It becomes unlink-and-reconcile: the container link is nulled, the intent decides. This reverses ADR-065's library reason on purpose. It can now only happen to a title the person put on the ladder themselves, which is the difference that makes it right.

## Deletions

- `ReleaseTracking.AutoTrack`, `ReleaseTracking.AutoTrackJob`
- `ReleaseTracking.Scanner` (no caller in `lib/`), and movie-collection tracking with it
- `ReleaseTracking.Reasons`, `ReleaseTracking.WatchlistListener`
- `plans.ex:155`'s `ensure_tracked/1`, `plans.ex:454`'s `ensure_tracking_item/1`
- `ReleaseTracking.update_automation/2` — it splits: the rung half becomes `set_rung/3`, the quality half becomes the Acquisition record's write
- `Item.tracking_mode` and the four quality columns
- The watchlist add/remove control and its two events
- `reasons_test.exs`, `scanner_test.exs` — the behaviour they guard is gone. Outside ADR-027's scope, which covers parser and pipeline regression tests.

## Migration

Paired migrations, idempotent backfill, one release.

1. `title_intents.rung` added; `watchlist_items` renamed.
2. For every intent: `rung` = the tracked item's `tracking_mode` when one exists above `:none`, else `:list`. `:watch` maps to `:follow`, `:global` to `:default`.
3. **Every tracked title with no intent row stops.** Delete the item, its releases and its wants. This is the decision recorded in the campaign, and it is the whole behaviour change on upgrade.
4. Tracked items at `:none` are deleted; if listed, the intent stays at `:list`.
5. Download params copied to the Acquisition record; the four columns dropped from `release_tracking_items`.
6. `tracking_mode` dropped.

On this install: 13 tracked titles, 7 with a watchlist entry, so **6 stop** — 11 sit at `:global`, 1 at `:watch`, 1 at `:none`, and 6 carry a library container. Collection trackers have no watchlist entry, so step 3 removes them without a special case.

Events survive item deletion (`on_delete: :nilify_all`, denormalised `item_name`). The campaign file said Off deletes events too; nothing reads an orphaned event and retention prunes them, so the FK is left alone rather than rebuilt. Flagged, not silently deviated from.

## Decision records

- New ADR superseding **ADR-065** §2 (the library reason), §4 (seeded modes — there is one write path now), §5 (the durable disarm) and the collection carve-out.
- New UIDR superseding **UIDR-035**'s "`Remove from watchlist` becomes the separate, unrelated act it always should have been" — under one ladder, removal *is* the bottom rung. The rest of UIDR-035 stands and is strengthened: the control is the same control everywhere, and now there is one of it.
- Glossary above elevated to `docs/GLOSSARY.md` at completion.

## Tests

Test-first per `automated-testing`. The load-bearing cases:

- `TitleIntent` rung ordering and the grab mapping — pure, no database.
- `set_rung/3` across every transition: Off→Grab creates machinery; Grab→List deletes it; List→Off deletes the record; raising an already-followed title moves the rung without re-fetching TMDB.
- The completion rule: a film at `:grab` landing in the library loses its machinery and keeps its rung.
- Deleting a library container unlinks rather than deletes.
- The two bug fixes: "Also grab future episodes" ends at a rung that actually grabs; the gap button ends at a rung that holds its wants.
- Migration: an integration test over the four starting shapes (listed+tracked, listed only, tracked only, tracked at `:none`).
- Storybook stories for the six-rung control — MC0009 will demand them anyway.

## Phases

Each leaves a working product.

1. **Download params leave release tracking.** New Acquisition record, migration, readers moved, `ensure_tracking_item/1` deleted. Accepting lower quality follows nothing.
2. **Nothing starts tracking on its own.** Delete `AutoTrack`, `AutoTrackJob`, `Scanner`, `plans.ex:155`. Still the two-table model; `arm/2` still the click path. After this the campaign's first completion criterion holds.
3. **One authored record.** `TitleIntent`, the rung, `set_rung/3`, the migration. `Reasons`, `WatchlistListener`, `arm`, `disarm`, `add_to_watchlist`, `remove_from_watchlist` and `Item.tracking_mode` all go.
4. **One control, honest acts.** Six-rung control replacing two controls; the third download-menu entry; the gap button and the grab-future checkbox set rungs that match their copy.
5. **Records and docs.** ADR, UIDR, `docs/GLOSSARY.md`, CHANGELOG in plain words, wiki (Settings reference, the Download menu, the Tracking control, Troubleshooting for the upgrade behaviour change).

Phase 2 must precede phase 3's migration, or `AutoTrack` would recreate what the migration removes.

## Deferred

- Any bulk arming surface for a freshly imported library. Decided against for now: import replaces with nothing. If Coming up turns out to be uselessly empty in practice, that is the thing to revisit first.
- `Item.name`'s duplication of `intent.title.name`. Left standing with reasons, not overlooked.
