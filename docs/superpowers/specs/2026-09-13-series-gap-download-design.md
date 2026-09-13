# Downloading what a series is missing — design

Date: 2026-09-13. Builds on the one-click download spec
(`2026-09-05-one-click-download-design.md`) and the download-button
default-action spec (`2026-09-12-download-button-default-action-design.md`),
which between them established the plan doors, the planning mode and the
approval policy this spec reuses without changing.

## Glossary

- **Season list** (existing) — the accordion of seasons in the TV detail modal. `MediaCentaurWeb.Components.Detail.SeasonList`, rendering the `%SeasonView{}` list that `ViewModel.SeriesDetail` composes.
- **Library episode row** (existing) — a season-list row for an episode with a file. `EpisodeListItem.Library`.
- **Missing episode row** (existing) — a dim, italic season-list placeholder for an episode number the library has no row for. `EpisodeListItem.Missing`. Today it means only "TMDB's episode count for this season is higher than the number of rows we have"; this spec makes it mean *aired and absent*.
- **Upcoming episode row** (existing) — a season-list row for an episode that has not aired, carrying an air-date pill. `EpisodeListItem.Upcoming`. Today it is only ever produced from release-tracking `Release` rows, so only tracked series get it.
- **Season episode dates** — a new `library_seasons` column holding TMDB's air date per episode number for that season, including episodes the library has no file for. Column `episode_air_dates`. The fact that lets the season list tell a missing episode from an unaired one without asking TMDB.
- **Targeting selection** (existing) — the full TMDB universe for a series: every season, every episode, each annotated `aired?` / `in_library?` / `tracked?`. `Acquisition.Targeting.series_selection/2`, one `get_tv` plus one `get_season` per season.
- **Plan** (existing) — a durable draft acquisition covering a chosen list of `{season, episode}` units. Created here through the existing door `Plans.create_series_plan/3`.
- **Planning mode** (existing) — what a download control does when pressed: *auto-select best release* (approval policy `automatic`) or *manually select release* (approval policy `review`, landing on the plan board). The person's default lives in `Settings.Preferences.PlanningMode`.
- **Plan modal / targeting stage** (existing) — the picker on Incoming, opened by `/incoming?plan=new&tmdb_id=<id>&tmdb_type=tv`: every season with what you own greyed out, and the presets *Everything aired* / *Continue* / *Latest season*.
- **Library Maintenance** (existing) — the Settings card of one-shot, idempotent, rate-limited passes over the library (*Refresh series credits*, *Repair missing images*, …). `MediaCentaur.Maintenance`.
- **Detail projection** (existing) — the ETS-backed read model the detail modal loads from. `Library.Views.Detail` / `Library.Views.DetailItem`.

## Problem

A series in the library is often incomplete, in two different shapes, and
the app offers no way to act on either from where you notice it.

**A hole inside a season you own.** The season list already draws a dim
placeholder for it. The row is focusable and does nothing. To download that
one episode you must leave the modal, go to Incoming, search the series
again, open the picker and find the episode.

**Seasons you don't own at all.** These do not render. The season list is
built from library seasons plus future seasons derived from release-tracking
`Release` rows, and those exist only for tracked titles. For an untracked
series the modal shows what is on disk and gives no sign the rest exists.
Both shapes are common in this library, and backfilling *earlier* seasons is
at least as common as getting the next one:

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
`number_of_seasons` is stale, which is one reason nothing in this spec
enumerates seasons from local metadata.)

Underneath both sits a correctness problem. A missing episode row is
produced whenever `Season.number_of_episodes` exceeds the rows we hold, with
no reference to whether the episode has aired. Making that row actionable
would offer to download episodes that do not exist yet.

## Decisions

### Controls

1. **The missing episode row becomes actionable.** Clicking it downloads
   that one episode. It keeps its place and its dim treatment at rest; on
   hover and on focus it lifts out of `opacity-30` and shows a download
   glyph in the row's right-hand slot — the same slot the upcoming row uses
   for its date pill. It stays a `data-nav-item`, as it already is.

2. **Offered only when a download could actually happen:** the series has a
   TMDB id and `acquisition?` is true (an indexer and a download client are
   configured). Otherwise the row renders exactly as it does today, inert.

3. **"Download more of this show" closes the season list.** A link after the
   last season section and before the entity-level extras, going to
   `/incoming?plan=new&tmdb_id=<id>&tmdb_type=tv` — the plan modal's
   targeting stage, which already fetches the series, greys out what you
   own and offers the presets. Same gating as decision 2. A `data-nav-item`,
   so the couch reaches it.

   This is the whole answer to "I only took one season to try it". No new
   picker, no new plumbing: a link and a render condition.

4. **Seasons the library does not have are still not rendered.** The season
   list stays a picture of what is on disk. Getting more of a series is the
   link's job, and the picker on the other side of it is where seasons you
   don't own belong.

### The action

5. **The click plans exactly one unit through the existing door.** The
   injected `EntityModal` clause handles `download_missing_episode`
   (`phx-value-season`, `phx-value-episode`) on the host, under
   `start_async`: `Targeting.series_selection(tmdb_id)`, then
   `Plans.create_series_plan(selection, [{season, episode}], approval_policy: policy)`.
   No new plan door, so `Plans.Doors.registry/0` and MC0037 are untouched.

6. **The planning mode decides the policy and the ending**, the same
   mapping the Download button uses: *auto-select best release* →
   `"automatic"`, flash `Finding a release for <series> S<n>E<n>`;
   *manually select release* → `"review"`, then navigate to the plan board
   at `/incoming?plan=<id>`. No menu on the row — one granularity, one
   verb. A click while one is pending is a no-op, and the pending row shows
   it.

7. **The fetched selection is the guard.** Before planning, check the unit
   in the selection: not `aired?`, or already `in_library?`, and nothing is
   planned — flash the reason instead. The selection is in hand at that
   point, so this costs nothing and keeps a stale projection from planning
   an episode that has since arrived.

8. **TMDB is fetched on the click, never on render.** Decision 5's
   `series_selection` is one `get_tv` plus one `get_season` per season,
   response-cached, on an explicit action — the same cost the Download
   button on a title already pays. Nothing in this spec fetches on modal
   open or on season expand.

### Telling missing from unaired

9. **`library_seasons` gains `episode_air_dates`**, `{:map, :date}` keyed by
   episode number as a string (`%{"13" => ~D[2003-02-20]}`). Nil for seasons
   ingested before the column and not yet backfilled; an episode number
   absent from a present map means TMDB gave that episode no date.

10. **It is written from a payload the app already fetches.**
    `Pipeline.Stages.FetchMetadata.build_season/2` receives the full
    `get_season` response and keeps `length(episodes)` from it; it now also
    builds the date map, and `Library.Inbound` persists it on the season
    upsert. Zero new TMDB calls at ingest.

11. **`SeriesDetail.build_library_items/4` consults it.** For an episode
    number with no library row and no release row:

    | season episode dates say | row |
    |---|---|
    | a date after today | `Upcoming`, `sub_status: :unaired`, with that air date |
    | a date today or earlier | `Missing` — actionable |
    | nothing (no map, or no entry) | `Missing` — today's behaviour |

    Unknown stays `Missing`: absence of a date is not evidence the episode
    is in the future, and the guard in decision 7 catches it at the click.
    Release rows still win over both, so tracked series are unaffected.

12. **The detail projection carries the new field.**
    `Library.Views.DetailItem.Season` gains `episode_air_dates` and
    `Library.Views.Detail` populates it, or the modal never sees the column.

### Backfill

13. **A Library Maintenance pass, `Maintenance.backfill_season_air_dates/0`**
    (plus the `_async/1` sibling every task has), surfaced as its own button
    on the Library Maintenance card. Iterates seasons whose
    `episode_air_dates` is nil or empty, belonging to a series with a TMDB
    id; one `get_season` per season, rate-limited inside the TMDB client;
    writes the map. Skips seasons that already have one, so re-running is
    free. A failed season is logged and skipped, leaving the rest intact.
    Returns `{:ok, %{updated:, skipped:, failed:}}` like its siblings, and
    broadcasts `entities_changed` so the detail projection refreshes.

14. **It is a separate pass, not a widening of *Refresh series credits*.**
    That task already walks every season with the same call and could carry
    this, but it is documented and named as a credits backfill and skips
    series whose credits are already populated — every series in this library today. A
    task that does two things and reaches the wrong set is worse than a
    second button.

15. **A season with no dates behaves as it does today.** The feature
    degrades to the current rendering rather than breaking, so the backfill
    is a correctness improvement you run once, not a prerequisite for
    shipping.

## What this does not do

- **Movie collections.** "You have 2 of 5 films" is the same shape and wants
  the same link, but it is a separate composer (`CollectionDetail`) and a
  separate change.
- **The Status page's "Incomplete seasons" tile.** It counts *series* with
  an internal numbering hole — 2, where counting seasons short of TMDB's
  count gives 6 series and 24 episodes — and its row links nowhere. Left
  exactly as it is: managing gaps is the owner's business, not something the
  app should drive from a dashboard.
- **Episode titles on the missing row.** The season payload carries them and
  the column could hold them, but the row reads "Episode 13" today and
  changing that is a spoiler decision, not part of this.

## Rejected

- **Rendering absent seasons in the season list**, dim, either individually
  or folded into one "Seasons 1–14 not in your library" row. The owner does
  not want seasons that aren't on disk appearing in the TV detail view; the
  list is about the library, and the picker is where the rest of the series
  lives.
- **Fetching a season from TMDB when it expands** to get air dates. Rejected
  by the owner: no TMDB calls in the render path. Decisions 9–13 exist
  because of this.
- **Lazily backfilling air dates on first open**, one call per gapped season
  for the life of the install. Cheaper to build and self-healing, but it
  still puts a TMDB call inside a modal open. The owner chose the explicit
  maintenance task.
- **A gap-remediation surface** — a list of every hole with a "fix" button,
  reached from the Status tile. Not wanted: the app should make the holes
  actionable where you meet them, not manage them for you.
- **A new plan door** for single-unit downloads. `create_series_plan/3`
  already means "these units of this series"; a one-element list is not a
  new kind of plan.

## Work

Test-first throughout (`automated-testing`), no network in tests.

1. Migration adding `episode_air_dates` to `library_seasons`; schema field;
   `DetailItem.Season` field and the `Views.Detail` population.
2. `FetchMetadata.build_season/2` builds the map; `Inbound` persists it.
3. `SeriesDetail.build_library_items/4` gains the three-way rule — pure,
   unit-tested against fixtures with no database.
4. `Maintenance.backfill_season_air_dates/0` + `_async/1`, the Settings
   button, and a task test against the TMDB stub.
5. The missing row's click affordance and the "Download more of this show"
   link in `SeasonList`; the `download_missing_episode` clause on
   `EntityModal`; a LiveView test for the plan call and for both gates.
6. Storybook: `SeasonList` is `@storybook_status :skip`, its states pinned
   by the `detail_panel` story's TV variations — add variations for an
   actionable missing row, an unaired placeholder, and the link present
   and absent (MC0009 / the `storybook` skill).
7. Copy for the link, the flashes and the maintenance button through the
   `writing-copy` skill.
8. Wiki: `Settings-Reference.md` for the maintenance task, and the TV detail
   page under *Using Media Centaur* for the two new controls.
