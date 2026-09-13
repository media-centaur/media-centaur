# Downloading what a series is missing — design

Date: 2026-09-13. Builds on the one-click download spec
(`2026-09-05-one-click-download-design.md`) and the download-button
default-action spec (`2026-09-12-download-button-default-action-design.md`),
which between them established the plan doors, the planning mode and the
approval policy this spec reuses without changing.

Revised the same day after a `unify_design` pass. The first draft added an
`episode_air_dates` column beside `Season.number_of_episodes` — two
projections of one TMDB payload. That draft's decisions 9–15 are replaced by
decisions 1–5 below; see "Rejected".

## Core idea

**A season's episode list is one fact.** Everything the season list draws is
that list joined against the files you have and against today's date.

## Glossary

- **Episode list** — TMDB's ordered episodes for one season, including episodes the library holds no file for: `[%{episode_number, name, air_date}]`. New `library_seasons.episode_list` column. The season's single source for "what episodes exist"; `number_of_episodes` was a count of this same list and is removed.
- **Episode row** — one rendered line in the detail modal's season list, tagged `Library` (a file exists), `Missing` (aired, no file) or `Upcoming` (not aired yet). `MediaCentaurWeb.ViewModel.EpisodeRow`, renamed from `EpisodeListItem` so "episode list" names the data and "episode row" names the rendering. `MovieRow` (from `MovieListItem`) is its collection sibling.
- **Season list** (existing) — the accordion of seasons in the TV detail modal. `MediaCentaurWeb.Components.Detail.SeasonList`, rendering the `%SeasonView{}` list `ViewModel.SeriesDetail` composes.
- **Targeting selection** (existing) — the full TMDB universe for a series: every season, every episode, each annotated `aired?` / `in_library?` / `tracked?`. `Acquisition.Targeting.series_selection/2`, one `get_tv` plus one `get_season` per season.
- **Plan** (existing) — a durable draft acquisition covering a chosen list of `{season, episode}` units. Created here through the existing door `Plans.create_series_plan/3`.
- **Planning mode** (existing) — what a download control does when pressed: *auto-select best release* (approval policy `automatic`) or *manually select release* (approval policy `review`, landing on the plan board). The person's default lives in `Settings.Preferences.PlanningMode`.
- **Plan modal / targeting stage** (existing) — the picker on Incoming, opened by `/incoming?plan=new&tmdb_id=<id>&tmdb_type=tv`: every season with what you own greyed out, and the presets *Everything aired* / *Continue* / *Latest season*.
- **Library Maintenance** (existing) — the Settings card of one-shot, idempotent, rate-limited passes over the library. `MediaCentaur.Maintenance`.

## Problem

A series in the library is often incomplete, in two shapes, and the app
offers no way to act on either from where you notice it.

**A hole inside a season you own.** The season list already draws a dim
placeholder. The row is focusable and does nothing. Downloading that one
episode means leaving the modal, going to Incoming, searching the series
again and finding the episode in the picker.

**Seasons you don't own at all.** These do not render. The season list is
built from library seasons plus future seasons derived from release-tracking
`Release` rows, and those exist only for tracked titles. Backfilling
*earlier* seasons is at least as common as getting the next one:

```
DAVE                have [3]            of 3
Fallout             have [2]            of 2
The Boys            have [3,4,5]        of 5
Futurama            have [9,10,11]      of 11
Murphy Brown        have [1,10]         of 10
It's Always Sunny   have [15,16,17,18]  of 17*
Scrubs              have [1..8]         of 9
```

(\*Sunny reads 17 while a library season 18 exists — the stored
`TVSeries.number_of_seasons` is stale, which is one reason nothing here
enumerates seasons from local metadata.)

Underneath both sits the modelling problem. The season list has no episode
list to render. It has a *count* (`Season.number_of_episodes`) and it
synthesizes numbers `1..count`, calling any number without a library row
`Missing` — with no reference to whether that episode has aired. Making
those rows actionable would offer to download episodes that don't exist yet.

## Decisions

### The episode list

1. **`library_seasons.number_of_episodes` is replaced by `episode_list`**, an
   embedded ordered list of `%{episode_number, name, air_date}`. The count
   becomes `length(episode_list)`. One column out, one in; no compatibility
   shim, per the house rule on obsolete paths.

2. **It is written from a payload the app already fetches and discards.**
   `Pipeline.Stages.FetchMetadata.build_season/2` receives the whole
   `get_season` response and keeps `length(episodes)` from it; it now builds
   the list instead. `Library.Inbound` persists it. Zero new TMDB calls at
   ingest. `Showcase` does the same from its fixture payloads. The no-TMDB
   path (`build_minimal_season/1`, `Inbound` line 683) writes `[]`.

3. **`Mapper.season_attrs/2` is deleted.** It extracts season attrs from the
   same payload, has no production callers, and is kept alive only by its own
   test — a second extraction of the fact this spec is unifying.

4. **`SeriesDetail.build_library_items/4` iterates the episode list.** For
   each entry: a library episode row exists → `EpisodeRow.Library`; else the
   air date is today or earlier, or absent → `EpisodeRow.Missing`; else →
   `EpisodeRow.Upcoming` with that air date and `sub_status: :unaired`.
   Library or release rows numbered outside the list still get their own row,
   appended in number order. The `ceiling` / `known_numbers` / gap-fill range
   logic goes away — it existed only because there was no list.

   An absent air date stays `Missing`: not knowing when an episode airs is
   not evidence that it is in the future, and decision 9's guard catches it
   at the click.

5. **Release rows still win where they exist.** For a tracked series the
   release-tracking calendar is fresher than an ingest-time snapshot and
   carries episode titles, so it overrides both `Missing` and `Upcoming` for
   the same `{season, episode}`, exactly as today. The two are not merged —
   see "Explicit non-convergence".

### Naming

6. **`ViewModel.EpisodeListItem` becomes `ViewModel.EpisodeRow`**, and its
   sibling `MovieListItem` becomes `MovieRow`. "Episode list" now names the
   data; "episode row" names the rendering, which is already the components'
   own vocabulary (`missing_episode_row`, `upcoming_episode_row`,
   `Detail.PlayableRow`, `row_class/2`). The two rename together because
   `MovieListItem`'s moduledoc defines it as the episode one's parallel.

7. **`Library.EpisodeList` becomes `Library.EpisodeOrder`** and
   `Library.MovieList` becomes `Library.MovieOrder`, and the three progress
   functions that belong to neither — `state_from_progress/1`,
   `progress_container_id/1`, `index_progress_by_key/1` — move to
   `Library.ProgressRecords`, which already owns progress records and is
   currently write-only.

   This is the third claimant on the words "episode list". The split is what
   makes the rename worth doing rather than cosmetic: the module's moduledoc
   is an "and" (walking a series' episodes *and* indexing progress records),
   `MovieList` carries no progress functions at all, and `CollectionDetail`
   — a movie view model — currently calls `EpisodeList.state_from_progress/1`.
   With the progress trio gone, what remains in both modules is ordering and
   position lookup over a container's children, which is what `Order` names.

### Controls

8. **The missing episode row becomes actionable.** Clicking it downloads that
   one episode. It keeps its dim treatment at rest; on hover and on focus it
   lifts out of `opacity-30` and shows a download glyph in the row's
   right-hand slot — the slot the upcoming row uses for its date pill. It
   stays a `data-nav-item`, as it already is. Offered only when the series
   has a TMDB id and `acquisition?` is true; otherwise the row renders inert,
   as today.

9. **The click plans one unit through the existing door.** The injected
   `EntityModal` clause handles `download_missing_episode`
   (`phx-value-season`, `phx-value-episode`) under `start_async`:
   `Targeting.series_selection(tmdb_id)`, then
   `Plans.create_series_plan(selection, [{season, episode}], approval_policy: policy)`.
   No new plan door, so `Plans.Doors.registry/0` and MC0037 are untouched.
   Before planning, the fetched selection is the guard: not `aired?`, or
   already `in_library?`, and nothing is planned — flash the reason instead.

10. **The planning mode decides the policy and the ending**, the same mapping
    the Download button uses: *auto-select best release* → `"automatic"`,
    flash `Finding a release for <series> S<n>E<n>`; *manually select
    release* → `"review"`, then navigate to the plan board at
    `/incoming?plan=<id>`. No menu on the row — one granularity, one verb. A
    click while one is pending is a no-op, and the pending row shows it.

11. **"Download more of this show" closes the season list.** A link after the
    last season section and before the entity-level extras, going to
    `/incoming?plan=new&tmdb_id=<id>&tmdb_type=tv` — the plan modal's
    targeting stage, which already fetches the series, greys out what you own
    and offers the presets. Same gating as decision 8. A `data-nav-item`, so
    the couch reaches it. This is the whole answer to "I only took one season
    to try it": a link and a render condition.

12. **Seasons the library does not have are still not rendered.** The season
    list stays a picture of what is on disk. Getting more of a series is the
    link's job, and the picker on the other side of it is where seasons you
    don't own belong.

13. **TMDB is fetched on a click, never on render.** Decision 9's
    `series_selection` is one `get_tv` plus one `get_season` per season,
    response-cached, on an explicit action — the same cost the Download
    button on a title already pays. Nothing here fetches on modal open or on
    season expand.

### Keeping the episode list true

14. **A Library Maintenance pass, `Maintenance.refresh_episode_lists/0`**
    (plus the `_async/1` sibling every task has), on its own button. It
    refreshes **seasons that are not complete** — an empty episode list, or
    fewer library episode rows than list entries — for series with a TMDB id:
    one `get_season` each, rate-limited inside the TMDB client. Complete
    seasons are skipped. Returns `{:ok, %{updated:, skipped:, failed:}}` like
    its siblings and broadcasts `entities_changed` so the detail projection
    refreshes. A failed season is logged and skipped, leaving the rest intact.

15. **It refreshes rather than backfills.** A season's list is captured at
    first ingest, so a season that was mid-run then — or whose episode count
    TMDB later revised — would otherwise stay frozen. Refreshing exactly the
    incomplete seasons costs the same calls as a fill-the-empties pass on its
    first run and is self-correcting afterwards.

16. **It is a separate pass, not a widening of *Refresh series credits*.**
    That task already walks every season with the same call, but it is named
    and documented as a credits backfill and skips series whose credits are
    populated — every series in this library today, so folding this in would
    reach nothing.

17. **A season with an empty episode list behaves as it does today.** The
    feature degrades to the current rendering rather than breaking, so the
    pass is a correctness improvement you run once, not a prerequisite.

### Converging the other definition

18. **`Library.Completeness.incomplete_season_count/0` reads the episode
    list.** It currently counts *series* with an internal numbering hole
    among library rows — a heuristic that misses a season stopping early and
    cannot tell an unaired episode from an absent one. With the list present
    the answer is exact: seasons holding an entry that has aired and has no
    library episode row. `detect_season_gaps/1` and its unit tests are
    deleted with it.

    Two definitions of "incomplete season" cannot both stand once the data
    exists to settle it. **The visible consequence: the Status tile's number
    changes from 2 to 6** on this library. The tile stays a readout and its
    row still links nowhere — that part of the first draft is unchanged.

### Projection

19. **The detail projection carries the episode list.**
    `Library.Views.DetailItem.Season` swaps `number_of_episodes` for
    `episode_list` and `Library.Views.Detail` populates it, or the modal
    never sees the column.

## Explicit non-convergence

**Release rows and the episode list carry the same fields** —
`{season_number, episode_number, air_date, title}` — for a tracked series.
They are not merged. The calendar is a maintained projection with tracking
semantics (`released`, `in_library`) and its own retention policy, refreshed
on a cadence; the episode list is an ingest-time snapshot of what a season
contains. Converging them would restructure ReleaseTracking for no gain in
this slice. The precedence rule (calendar wins) is documented on
`SeriesDetail.build/4`.

## Out of slice

- **`TVSeries.number_of_seasons` is stale and rendered.**
  `Detail.TitlePreview` shows it via `seasons_label/1`; Sunny reads 17 with a
  library season 18 present. Nothing in this design reads it and no decision
  here depends on it. Recorded, not fixed.
- **Movie collections.** "You have 2 of 5 films" is the same shape and wants
  the same link, but it is a separate composer (`CollectionDetail`) and a
  separate change.
- **Dissolving `EpisodeOrder` / `MovieOrder` entirely** into their consumers
  (`Playback.ResumeTarget`, `ProgressSummary`) rather than renaming them.
  That is the fuller answer to two helper grab-bags, and it is a bigger
  design change than this feature earns. Decision 7 removes the "and" from
  their moduledocs, which is the part that matters here.
- **Episode titles on the missing row.** The episode list now holds them, so
  this becomes a copy and spoiler decision rather than a data one. Not taken.

## Rejected

- **`Season.episode_air_dates` as a new column beside `number_of_episodes`**
  (the first draft's decision 9). Two projections of one payload: a count of
  the episode list, and a map of part of the episode list. Cheaper — one
  added column and one added read site — and it leaves the next person to
  touch the season list inheriting both.
- **Rendering absent seasons in the season list**, dim, individually or
  folded into one "Seasons 1–14 not in your library" row. The owner does not
  want seasons that aren't on disk appearing in the TV detail view.
- **Fetching a season from TMDB when it expands** to get air dates. No TMDB
  in the render path; decisions 1–2 exist because of this.
- **Lazily filling the episode list on first open**, one call per incomplete
  season for the life of the install. Self-healing and cheaper to build, but
  it still puts a TMDB call inside a modal open. The maintenance pass is
  explicit instead.
- **A gap-remediation surface** — a list of every hole with a "fix" button,
  reached from the Status tile. The app should make holes actionable where
  you meet them, not manage them for you.
- **A new plan door** for single-unit downloads. `create_series_plan/3`
  already means "these units of this series"; a one-element list is not a new
  kind of plan.

## Work

Test-first throughout (`automated-testing`), no network in tests. The renames
are mechanical and `mix precommit` polices them; they land first and
separately so the feature work can be reviewed apart from the churn.

**Renames (no behaviour change):**

1. `ViewModel.EpisodeListItem` → `EpisodeRow`, `MovieListItem` → `MovieRow`.
   ~162 references across 19 files, storybook included.
2. `Library.EpisodeList` → `EpisodeOrder`, `MovieList` → `MovieOrder`; the
   progress trio moves to `Library.ProgressRecords`. ~110 references across
   23 files.

**The episode list:**

3. Migration adding `episode_list` and dropping `number_of_episodes`; schema
   field; `DetailItem.Season` and `Views.Detail` swapped over.
4. `FetchMetadata.build_season/2` and `Showcase` build the list; `Inbound`
   persists it; `Mapper.season_attrs/2` and its test deleted.
5. `SeriesDetail.build_library_items/4` rewritten against the list — pure,
   unit-tested from fixtures with no database.
6. `Completeness.incomplete_season_count/0` rewritten; `detect_season_gaps/1`
   and its tests deleted.
7. `Maintenance.refresh_episode_lists/0` + `_async/1`, the Settings button,
   and a task test against the TMDB stub.

**The feature:**

8. The missing row's click affordance and the "Download more of this show"
   link in `SeasonList`; the `download_missing_episode` clause on
   `EntityModal`; a LiveView test for the plan call and for both gates.
9. Storybook: `SeasonList` is `@storybook_status :skip`, its states pinned by
   the `detail_panel` story's TV variations — add variations for an
   actionable missing row, an unaired placeholder, and the link present and
   absent (MC0009 / the `storybook` skill).
10. Copy for the link, the flashes and the maintenance button through the
    `writing-copy` skill.
11. Wiki: `Settings-Reference.md` for the maintenance pass, and the TV detail
    page under *Using Media Centaur* for the two new controls.
