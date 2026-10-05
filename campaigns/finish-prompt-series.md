---
status: planning
started: 2026-10-05
last_updated: 2026-10-05
---
# Finish prompt for series

## Glossary

- **Completion** — a playable item (movie, episode, extra, video object)
  reaching its end: a credits/outro chapter in the back 20% of the file,
  or 90% of the duration. Judged by `Playback.Completion.reason/3`.
- **Session** — one `MpvSession`: one mpv process, from launch to mpv
  closing. Keyed by the session's entity id.
- **Viewing chain** — a TV session that rolls from one episode into the
  next inside the same mpv process (ADR-062). One session, several
  episodes.
- **Session end** — `MpvSession.finalize/1`: `PlaybackStateChanged
  :stopped`, then `SessionEnded{entity_id, completed}`.
- **Finish prompt** — the row above the title detail's action row:
  "You finished *X*", then Review, the primary delete, Done
  (`Components.Detail.FinishPrompt`). Provisional name and copy.
- **Standalone movie** — a movie entity with no `movie_series_id`; it is
  its own session entity.
- **Primary delete** — the Manage panel's "Delete this file / Delete all
  files": every file the library holds for the open entity
  (`Components.Detail.DeleteAllButton`, `delete_all_prompt`).

## Goal

Offer the finish prompt when the person finishes a **series**, as v1.53.0
does for a standalone movie: the moment a show ends is when reviewing it,
or clearing it off disk, is most natural. The open question is what
"finished a series" means and which acts fit that moment; the plumbing
from the movie version is reusable as is.

## Status

Planning. The movie version shipped in v1.53.0 (2026-10-05). Nothing
built for series. The next session starts with the design questions
below, with the owner.

## What exists, and why (v1.53.0)

Design: [`plans/005-movie-finish-prompt.md`](../plans/005-movie-finish-prompt.md),
decision: [UIDR-052](../decisions/user-interface/2026-10-05-052-a-completed-movie-opens-its-title.md)
(status still `proposed`). Commit `3a0df855`, released as v1.53.0.

**Behaviour.** Closing mpv on a standalone movie the session completed
opens that movie's title detail with the finish prompt. If the movie's
detail is already open it stays on its view and gains the row; another
title's modal is replaced. Done hides the row; closing the modal or a
reload drops it. Settings → Preferences → *Ask after finishing a movie*
(`movie_finish_prompt`, default on) turns it off.

**Why it is shaped this way** — each was a decision with an alternative:

1. **The app asks, not mpv.** An mpv Lua overlay could take a sentiment
   but not review text, and Delete would need a new mpv → app channel.
   The app already owns Review and Delete on the title detail, with
   keyboard/gamepad navigation. (UIDR-052.)
2. **The prompt is the title detail, not a new dialog.** Review
   (`review_open`, `ReviewFlow`) and the primary delete (arm gesture,
   async delete, playing guard) already have one owner,
   `TitleDetailHost`. A separate dialog would have been a second copy of
   all three. The feature is a way *into* the detail at a moment.
3. **The session states what it completed.** Completion used to be
   judged inside the detached persistence task, so the session process
   never knew. The judgment moved into the session
   (`MpvSession.judge_completion/1`, applying `Playback.Completion`, which
   also absorbed `ChapterCompletion` and the extras' separate 90% rule);
   only the write stays in the task. `completed` is a `MapSet` of
   `{:movie | :episode | :video_object | :extra, id}` — **a viewing chain
   already lists every episode it finished**, so series needs no backend
   change to know what was watched in a session.
4. **A separate event, after `:stopped`.** `SessionEnded` rather than a
   field on `PlaybackStateChanged` (meaningless for `:playing`/`:paused`).
   It follows `:stopped` on the same topic from the same process, so the
   host has dropped the entity from its playing set before Delete can arm.
5. **The web layer decides.** `TitleDetailHost.Finish.reaction/3` (pure)
   returns `:ignore | {:in_place, id} | {:open, id}` from the payload, the
   open detail's entity id, and the preference. It map-matches the payload
   (`Playback.Events` structs are not exported across the boundary). The
   host sets `:finished_entity_id` and, for `:open`, patches
   `?entity=<id>`.
6. **Prompt state is a host assign, not `ModalState`.** `ModalState` is
   replaced on every open, and `?entity=` canonicalises through a second
   patch, so a flag set at event time would be lost. `:finished_entity_id`
   sits beside `:title_playback`; `DetailPanel` draws the row while it
   equals the open entity; another title taking the modal or a close
   clears it.
7. **In place does not patch.** A patch without `view` would reset the
   open detail to its main view.
8. **One delete button.** `DeleteAllButton` was extracted from the Manage
   panel; both surfaces draw it.
9. **Navigation.** `detail_finish` is a TOOLBAR zone, first in the detail
   overlay's `entry` list, between `detail_social` and `detail_actions`;
   no `back` edge, so BACK closes the modal.

**Why collections were excluded.** A movie in a collection plays under
the collection's entity (`Resolver.resolve_movie_parent/1` →
`:movie_series`), so `SessionEnded.entity_id` is the collection and the
completed item is `{:movie, member_id}`. The primary delete on that detail
removes every movie in the collection. `Finish.reaction/3` matches only
`{:movie, entity_id}`, which excludes them by construction.

## Design questions for series

Series has the same shape problem as collections: the session entity is
the container (`:tv_series`), the completed items are its children
(`{:episode, id}`), and the primary delete removes the whole show.

1. **What is "finished a series"?** Candidates, each needing different
   facts:
   - the session completed the **last episode the library holds** (the
     chain's natural end — `NextEpisode.resolve/1` returns `:none`);
   - **every** episode is now complete (library progress, not just this
     session);
   - the **last aired episode of a show TMDB marks as ended** (the
     `TMDB.Store` record knows status; an ongoing show is never
     "finished", only "caught up");
   - a **season finale** (finished a season, not the series).
   The movie rule was "completed during this session"; decide whether the
   series rule is the same plus a position test, or a library-wide test.
2. **Which acts fit?**
   - **Review** — a review is per TMDB title (`tmdb:tv_series:<id>`),
     so reviewing the show works unchanged.
   - **Delete** — the primary delete removes every file of the show. Is
     that the act, or "delete the season(s) just watched", or "delete
     watched episodes"? The latter needs a delete target the Manage panel
     does not have today (it has file, folder, all).
   - **Watchlist / tracking** — for an ongoing show, "keep following for
     new episodes" vs "stop following" may matter more than delete. The
     ladder and its controls live in `Title.TrackingControls` (UIDR-042).
   - **Done**.
3. **Caught up vs finished.** If the show is ongoing, does the prompt say
   something different ("You're caught up") and offer different acts?
4. **Mid-series sessions.** A session that completes episodes but not the
   last one: nothing (play in place holds), as for an incomplete movie?
5. **The setting.** Extend `movie_finish_prompt` to cover series (rename
   key and label — no backward compatibility needed), or a second toggle?
6. **Collections.** Same question as (1) for a movie collection
   ("finished the last movie"), and the per-movie delete target. Fold in
   here or leave deferred.
7. **Where the rule lives.** Today `Finish.reaction/3` gets only the
   payload, the open entity id and the preference. A series rule needs
   library or TMDB facts (episode order, show status). Decide whether the
   host reads them, or the session/`Playback` states "chain ended at the
   last episode" in `SessionEnded` (it knows when `NextEpisode` returned
   `:none`). Run the unify pass on that choice.

## Decisions made

* `2026-10-05` — Movie finish prompt: the app asks, on the title detail,
  driven by `SessionEnded`; standalone movies only. ([UIDR-052](../decisions/user-interface/2026-10-05-052-a-completed-movie-opens-its-title.md), [plan 005](../plans/005-movie-finish-prompt.md), commit `3a0df855`, v1.53.0)
* `2026-10-05` — Series and collections deferred to this campaign: the
  session entity is the container and the primary delete would remove all
  of it.

## Next steps

1. Reconcile this file against `git log` and the code (CLAUDE.md
   campaign rule).
2. Design session with the owner on questions 1–3 and 5 (the trigger, the
   acts, caught up vs finished, the setting). Load `unify_design` and run
   it over the chosen trigger before planning.
3. Amend UIDR-052 (or add a UIDR) for series; write `plans/006-…`.
4. Build test-first, as plan 005 did; stories for any changed component.
5. Carried from the movie version (do alongside, or close separately):
   - owner copy pass on "You finished …" and the setting label;
   - `mc-nav-trace` check that a modal opened by a finish lands the cursor
     in `detail_finish`;
   - one real end-to-end run: finish a movie in mpv and close it;
   - UIDR-052 from `proposed` to `accepted` once verified.

## Completion criteria

* Closing mpv after finishing a series (by the agreed rule) opens the
  show's detail with a finish prompt whose acts were agreed with the
  owner, behind the agreed setting.
* Collections either handled or explicitly declined in this file.
* UIDR(s) accepted; wiki (Playback, Settings-Reference) updated; tests
  and stories cover the series states.

## Pointers

- Backend: `lib/media_centaur/playback/mpv_session.ex`
  (`judge_completion/1`, `session_ended/1`, `finalize/1`,
  `advance_to/2`), `lib/media_centaur/playback/completion.ex`,
  `lib/media_centaur/playback/events.ex` (`SessionEnded`),
  `lib/media_centaur/playback/next_episode.ex` (chain end),
  `lib/media_centaur/playback/resolver.ex` (session entity per type).
- Web: `lib/media_centaur_web/live/title_detail_host.ex` (§ The finish
  prompt), `lib/media_centaur_web/live/title_detail_host/finish.ex`,
  `lib/media_centaur_web/components/detail/finish_prompt.ex`,
  `lib/media_centaur_web/components/detail/delete_all_button.ex`,
  `lib/media_centaur_web/components/detail_panel.ex`,
  `assets/js/input/config.js` (`detail_finish`).
- Setting: `lib/media_centaur/settings/preferences/movie_finish_prompt.ex`,
  `lib/media_centaur_web/live/settings_live/preferences.ex`.
- Tests: `test/media_centaur_web/live/home_live_test.exs` (describe
  "finish prompt"), `test/media_centaur_web/live/title_detail_host/finish_test.exs`,
  `test/media_centaur/playback/mpv_session_test.exs`,
  `test/media_centaur/playback/completion_test.exs`.
- Related decisions: ADR-062 (viewing chain), UIDR-027 (play in place),
  UIDR-042 (tracking controls), UIDR-043 (one title detail), ADR-068 /
  UIDR-040 (reviews).
