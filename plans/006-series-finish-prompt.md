# Finish Prompt for Series and Collection Movies

Extends plan 005 (movie finish prompt, v1.53.0). Campaign:
[`campaigns/finish-prompt-series.md`](../campaigns/finish-prompt-series.md).

## Glossary

- **Completion**, **session end**, **finish prompt**, **primary delete** —
  as in plan 005 and the campaign glossary.
- **Latest aired episode** — the TMDB series record's `last_episode_to_air`
  (`season_number`, `episode_number`), read from `TMDB.Store`. For a show
  TMDB marks Ended or Canceled it is the finale; for a show still airing it
  is the newest episode out.
- **Settled series** — a series whose `TMDB.Store` record has `settled_at`
  set: TMDB status Ended or Canceled and no air date ahead
  (`TMDB.Schedule.plan/5`). A series that is not settled has a release
  ahead.
- **Collection movie** — a movie with a `movie_series_id`. It plays under
  the collection's entity, and its title detail is the collection's detail
  opened on that member (`LibraryHalf.load_entity/1` with the movie's id).
- **Finished id** — the library id the prompt belongs to: a standalone
  movie's id, a series' id, or a collection movie's own id (not the
  collection's). Replaces `finished_entity_id`'s container-only meaning.

## Problem Statement

v1.53.0 offers the finish prompt only for a standalone movie. Finishing a
show, or a movie that belongs to a collection, ends with nothing, though
these are the same moment to review the title or clear it off disk.

## User-Facing Behavior

- **Series, ended.** The session completed the latest aired episode of a
  settled series, and mpv closes. The show's detail opens with "You
  finished *Sample Show*": **Review**, **Delete all files**, **Done**.
- **Series, still airing.** The session completed the latest aired episode
  of a series that is not settled. The detail opens with "You're caught up
  on *Sample Show*": **Review**, the **Track release dates** switch,
  **Done**. No delete.
- **Series, anything else.** A session that completes earlier episodes
  only — including the last episode of the seasons the library holds when
  TMDB lists more — prompts nothing. A series with no TMDB record or no
  `last_episode_to_air` prompts nothing.
- **Collection movie.** Completing a movie in a collection is treated as
  finishing that movie: the collection's detail opens on that movie with
  "You finished *Movie A*": **Review** (the movie's TMDB title), **Delete**
  (that movie's files only, never the collection's), **Done**.
- **Standalone movie.** Unchanged from v1.53.0.
- Open / in place / another title's modal, Done, close, reload: as plan
  005, applied to the finished id.
- **Setting.** Settings → Preferences: "Ask after finishing a title"
  (provisional), key `finish_prompt`, default on. Replaces "Ask after
  finishing a movie" (`movie_finish_prompt`); the old key is dropped.
- **Track release dates on ended shows.** The switch no longer shows on a
  settled series (UIDR-042 rule 2: only while a release is ahead). This is
  the same fact that splits "finished" from "caught up".

## Design

### Core idea

The prompt appears when a session completed the final released item of the
title the person thinks of as watched: a movie (standalone or in a
collection), or a show's latest aired episode. What is "final" is a TMDB
fact for series; whether it was completed is a Playback fact. The web layer
is where both are readable, so it decides.

### Pieces

| Piece | Owner | Change |
|---|---|---|
| What the session completed | `MpvSession`, `Playback.Events.SessionEnded` | Episode items carry their numbers: `{:episode, id, season_number, episode_number}`. Movie, extra and video-object items unchanged. |
| Series identity for the lookup | `SessionEnded` | Add `tmdb_ref` (`{tmdb_id, :tv_series}` or nil), read once by the session from `Library.ExternalIds` when the session entity is a series. *Verify at implementation: whether the session already holds it; if a Library read is needed, do it at session start, not in `finalize/1`.* |
| Reaction | `TitleDetailHost.Finish.reaction/4` (pure) | Input: payload, the open detail's finished-id candidate, the preference, and the series' TMDB record (or nil). Output: `:ignore` \| `{:in_place, finished}` \| `{:open, finished}` where `finished` is `%{id, kind}` and `kind` is `:finished \| :caught_up`. Rules: standalone movie as today; a completed `{:movie, id}` with `id != entity_id` is a collection movie → finished id `id`; a completed episode matching the record's `last_episode_to_air` → finished id = the series id, kind by `settled_at`. |
| TMDB read | `TitleDetailHost.react/2` | Only when the payload holds an episode and a `tmdb_ref`: `TMDB.Store.get/1`. One read per subscribed page at session end. |
| Prompt state | host assign `:finished` (`%{id, kind}` or nil) | Replaces `:finished_entity_id`. `keep_finish_for/2` and `DetailPanel` compare against the open detail's **subject id**: the selected member's movie id when a member is selected, else the container id. New helper `LibraryHalf.subject_id/1` beside `container_id/1`. |
| Opening | host | `{:open, finished}` patches `?entity=<finished.id>`; for a collection movie this opens the collection on that member (`load_entity/1`). In place never patches (plan 005 §4). |
| Prompt row | `Detail.FinishPrompt` | Attr `kind` (`:finished \| :caught_up`) picks the heading and the middle act: the delete for `:finished`, `Title.TrackingControls`' Track switch for `:caught_up` (compose the existing switch; do not redraw it). Story covers both kinds, with and without Review, and the member delete. |
| Member delete | `Detail.DeleteAllButton` + `LibraryEvents` | The button takes the files it covers. For a collection member the prompt passes only that movie's files, and the gesture target is `{:member, movie_id}` so the Manage panel's `:all` (whole collection) is never armed from the prompt. *Verify at implementation: how a `KnownFile` maps to a member movie (`Library.Files.list_by_entity_id/1` returns the container's files).* |
| Releases ahead | `Title.Logic.release_ahead?/3` | Series branch: true unless the TMDB record is settled. The detail needs the settled fact for a library-owned series; carry it on `TitleDetail` (read with the record the detail already loads, or add it there). |
| Setting | `Settings.Preferences.FinishPrompt` | Rename from `MovieFinishPrompt`; key `finish_prompt`; label and help text cover any title. |

### Unify pass

1. **"Last episode the library lists" was wrong.** The library holds only
   the seasons it has files for (dev DB 2026-10-05: an ended four-season
   show with season 1 only). The final episode is a TMDB fact, so the rule
   moved from Playback to the web layer, where `TMDB.Store` is readable.
   Playback keeps stating only what it completed.
2. **`release_ahead?` was always true for a series.** The Track switch
   showed on ended shows. Fixed in this change; the prompt's finished /
   caught-up split reads the same fact. One fact, two consumers.
3. **The prompt belonged to a container.** `finished_entity_id` matched
   `container_id/1`, which cannot tell one collection member from another.
   The finished id is now the subject's id; the standalone movie and the
   series cases are unchanged because subject and container are the same.
4. **The primary delete for a collection movie.** `:all` on a collection
   deletes every member. The prompt must never arm that; a member target
   keeps the Manage panel's meaning of "Delete all files" intact.

### Ordering and delete protection

Unchanged: `SessionEnded` follows `:stopped` on the same topic from the
same process.

### Data Model Changes

None. The Settings key is renamed (`BooleanSetting`, no migration; the old
row is ignored).

### Integration Points

- `docs/playback.md`: `SessionEnded` item shapes and `tmdb_ref`.
- Wiki: `Settings-Reference.md` (renamed toggle), `Playback.md` (series,
  caught up, collection movies).

### Constraints

- UIDR-052 (amended 2026-10-05), UIDR-042 rule 2, UIDR-043, UIDR-027.
- Boundary: Playback does not depend on TMDB; the web layer does.
- MC0012: `playback:events` messages through `Playback.Events`.
- Compose from the kit: the Track switch and the delete button are reused.

## Acceptance Criteria

- [x] Completing the latest aired episode of a settled series: the show's
      detail opens with "You finished", Review, Delete all files, Done.
- [x] Same for a series that is not settled: "You're caught up", Review,
      Track release dates, Done; no delete.
- [x] Completing only earlier episodes, or the last held episode when TMDB
      lists later ones: nothing opens.
- [x] No TMDB record or no `last_episode_to_air`: nothing opens.
- [x] Completing a collection movie: the collection opens on that movie,
      "You finished *Movie A*"; Review targets the movie; Delete arms and
      deletes only that movie's files.
- [x] Standalone movie behaviour unchanged.
- [x] In place / open / another title's modal / Done / close / reload, for
      all three kinds.
- [x] Preference `finish_prompt` off: nothing opens for any kind.
- [x] Track release dates absent on a settled series' detail.
- [x] `FinishPrompt` story: finished, caught up, member delete, no Review.
- [x] Docs and wiki updated; UIDR-052 amendment in place.

## Decisions

- UIDR-052, amendment 2026-10-05.

## As built (2026-10-05)

Where the build departed from the Pieces table above:

- **No `tmdb_ref` on `SessionEnded`.** The host resolves the series'
  TMDB id itself (`Library.ExternalIds.tmdb_ids_for_tv_series/1`, then
  `TMDB.Store.get/1`), and only when the payload holds an episode
  (`Finish.episodes?/1`). The event states only what the session
  completed; the session process does no extra read.
- **`Finish.reaction/4`** takes the latest aired episode as
  `{season_number, episode_number}` (`Finish.latest_aired_episode/1`
  parses the payload), not the record.
- **The prompt state is `:finished_id`, a string.** The kind is not
  stored: `Detail.Logic.finish_prompt/3` derives `:finished` /
  `:caught_up` and the delete target at render, from the open detail's
  `settled?` fact — the same fact `Title.Logic.release_ahead?/2` reads.
  `Detail.Logic.subject_id/1` (not `LibraryHalf`) names the subject.
- **The Track switch** is `TrackingControls.track_switch/1`, drawn by the
  tracking controls and the prompt. From Off or Ignored it sets Follow,
  so a caught-up show not yet on the list can be tracked from the prompt.
- **The member delete** reuses `delete_all_prompt` with
  `phx-value-member`; the target is `{:member, movie_id}`.
  `Library.Files.list_by_entity_id/1` now preloads each file's
  `playable_item`, which `Detail.Logic.files_for_target/2` filters by.


## Smoke Tests

- `Finish.reaction/4`: standalone movie; collection movie; series finale,
  settled; latest episode, not settled; earlier episode; last held episode
  short of TMDB's; no record; preference off; in place vs open for each.
- `MpvSession`: an episode completion adds `{:episode, id, s, e}`;
  `session_ended/1` carries `tmdb_ref` for a series.
- `Title.Logic.release_ahead?/3`: settled series false, unsettled true.
- Host LiveView test (Home): broadcast `SessionEnded` for each kind →
  modal and prompt as specified; member delete arms `{:member, id}`.
- `FinishPrompt` and `DeleteAllButton` stories.
