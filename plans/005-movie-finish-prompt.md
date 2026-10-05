# Movie Finish Prompt

## Glossary

- **Completion** — the transition of a playable item to `completed: true`
  (`LibraryProgress.complete/1`): a credits/outro chapter reached, or 90% of
  duration. Once per viewing; a rewatch starts a fresh session at
  `completed: false`, so it completes again.
- **Session end** — `MpvSession.finalize/1`: mpv closed, progress persisted,
  `PlaybackStateChanged :stopped` broadcast.
- **Standalone movie** — a movie entity with no `movie_series_id`. A movie in
  a collection plays under the collection's entity (`:movie_series`).
- **Finish prompt** — the row at the top of the title detail modal that reads
  "You finished *Movie A*" and offers Review, Delete and Done. Provisional
  name and copy.

## Problem Statement

The moment a movie ends is when reviewing it or clearing it off disk is most
natural, and today both mean finding the title again. Review and Delete
already exist on the title detail modal; nothing brings that modal to the
person when a movie ends.

## User-Facing Behavior

- A standalone movie completes during a session and the person closes mpv.
  The app opens that movie's detail modal with the finish prompt at the top:
  **Review**, **Delete**, **Done**.
  - Played from a card or the hero (no modal open): the modal opens on the
    movie.
  - Played from the movie's own detail modal (modal still open): the modal
    stays, on the view it was on, and gains the prompt.
  - Another title's modal is open: the finished movie takes the modal, the
    same as any open of a different title.
- **Review** opens the existing Review modal on the movie (pre-filled from an
  earlier review, as today). A movie with no TMDB identity cannot be
  reviewed; its prompt shows Delete and Done only.
- **Delete** is the manage panel's primary delete (`delete_all_prompt`): the
  same click-twice arm, the same async delete, the same labels ("Delete this
  file (2.1 GB)"). On success the title leaves the library and the modal
  closes as it does today.
- **Done** dismisses the prompt; the modal stays open. Back/Esc closes the
  modal as usual.
- Closing mpv before completion, ending an extra, a TV episode or a movie in
  a collection: no prompt, the page is as the person left it (play-in-place
  holds).
- Settings → Preferences gains a toggle, on by default: "Ask after
  finishing a movie" (provisional copy). Off: no modal opens.
- Reload never shows the prompt: it is not in the URL.

## Design

### Core idea

A completed viewing is the moment to act on the title just watched. Review
and Delete are the title's own actions, already on its detail modal; the
feature is a way *into* that surface at that moment, not a new surface.

### Pieces

| Piece | Owner | Shape |
|---|---|---|
| Completion judgment | `Playback.Completion` (new, pure) | `reason/3` — moved out of `MpvSession`'s private `completion_reason/3`: credits chapter reached, or 90% |
| What the session completed | `MpvSession` | `completed` (`MapSet` of `{:movie \| :episode \| :video_object, id}`), added to in-process at each persist when `Completion.reason/3` says so; the detached write task keeps the `LibraryProgress.complete/1` call and its already-completed guard |
| Session-end fact | `Playback.Events` | new `SessionEnded{entity_id, completed}`, broadcast from `finalize/1` immediately after `PlaybackStateChanged :stopped` |
| Reaction | `TitleDetailHost` + pure `FinishPrompt.reaction/3` | `:ignore` / `:in_place` (the open detail's container is the entity) / `:open` (patch `?entity=<id>`); the host then sets `finished_entity_id` |
| Prompt state | host assign `finished_entity_id` | beside `title_playback`, not in `ModalState`; the prompt renders while it equals the open detail's container id; cleared by Done and on close |
| Delete control | `Detail.DeleteAllButton` (extracted from `ManagePanel`) | the one Delete-all armed button, drawn by the manage panel and the prompt |
| Finish prompt | `Detail.FinishPrompt` component | Review (`review_open`, gated like `ViewControls`: `review?` and a TMDB ref), `DeleteAllButton`, Done (`finish_prompt_done`); its own nav zone, the detail overlay's entry zone while shown |
| Preference | `Settings.Preferences.MovieFinishPrompt` | `BooleanSetting`, default `true`, read by the host when the event arrives; toggle under Settings → Preferences |

### Unify pass on the implementation

1. **The session did not know what it completed.** Completion was judged
   inside the detached persistence task, so the session process never
   saw it. Fixed now: the judgment (pure, from position, duration and
   chapters the session holds) runs in-process; only the write stays in
   the task. One judgment, one place.
2. **`ModalState` cannot carry the prompt.** It is replaced whenever the
   subject changes, and opening by `?entity=` canonicalises with a second
   patch, which would drop a flag set at event time. The prompt is a fact
   about an entity that precedes the open — the same shape as
   `title_playback` — so it is a host assign matched against the open
   detail.
3. **Delete-all is drawn inline in `ManagePanel`.** A second surface
   needs it, so it becomes one component used by both, not a copy.
4. **Already open on the movie** must not re-patch: a patch without
   `view` resets the view to main. `:in_place` sets the assign only.

Recovered sessions (ADR-023) start with an empty `completed` and refill
it from the next persist, because the judgment is a function of
position. `terminate/2` during app shutdown also finalizes and so also
broadcasts `SessionEnded`; the pages are shutting down with it, so no
prompt results.

### Why a separate event

`PlaybackStateChanged` is a state transition shared by `:playing`, `:paused`
and `:stopped`; a `completed` field would be meaningless on two of three.
The session, not the UI, knows what it completed — the UI combining
`watch_event_created` with `:stopped` would be a second source of truth.
`completed` is a list because a TV session already completes several
episodes in one chain today; only standalone movies react for now.

### Ordering and delete protection

The host's playing set (delete protection) must have dropped the movie
before Delete can arm. `SessionEnded` follows `:stopped` from the same
process on the same topic, so it is always seen after it. The test pins
this.

### Data Model Changes

None. One new Settings key (`BooleanSetting`, no migration).

### Integration Points

- `playback:events` gains `SessionEnded` (document it in `docs/playback.md`).
- No cross-repo spec.
- Wiki: `Settings-Reference.md` (the toggle), `Playback.md` (the finish
  prompt).

### Constraints

- UIDR-043 — the title detail modal and its single host.
- UIDR-052 — a completed movie opens its title (this change).
- Plan 003 (play in place) — return-to-page-as-left still holds for every
  case except a completed standalone movie with the preference on.
- MC0012 — every `playback:events` message goes through `Playback.Events`.
- Compose from the kit: Delete reuses the manage panel's arm button; no
  hand-rolled buttons.

### Cleanup in the same change

- `TitleDetailHost` moduledoc says "Home and Library follow" — all four
  pages use it now.

## Acceptance Criteria

- [x] Completing a standalone movie and closing mpv, played from a card: the
      detail modal opens on the movie with the finish prompt.
- [x] Same, played from the movie's open detail modal: the modal stays on
      its view and gains the prompt.
- [x] Same, another title's modal open: the movie takes the modal, prompt
      shown.
- [x] Closing before completion, extras, episodes, movies in a collection:
      no modal opens, no prompt.
- [x] Review opens the Review modal on the movie; absent without a TMDB
      identity.
- [x] Delete arms on first press and deletes on the second, exactly as the
      manage panel's primary delete; never blocked as "playing".
- [x] Done dismisses the prompt and leaves the modal open; reload never
      shows it.
- [x] Preference off: nothing opens.
- [x] Keyboard and gamepad reach Review, Delete and Done; the prompt is
      the modal's entry zone while shown.
- [x] Finish prompt component has a story covering its states.
- [x] `docs/playback.md` documents `SessionEnded`; wiki updated.

## Decisions

- See `decisions/user-interface/2026-10-05-052-a-completed-movie-opens-its-title.md`.

## Smoke Tests

- `Playback.Completion.reason/3`: chapter boundary, 90%, neither.
- `MpvSession` pure functions (struct-built like `queue_next?/1`): a
  persist past completion adds the current item; the end event carries
  the set.
- `FinishPrompt.reaction/3`: standalone movie, collection member,
  episode, preference off, already open, other title open.
- Host LiveView test (Home): broadcast `SessionEnded` → modal opens with
  the prompt; Done; preference off; already-open keeps its view.
- `DeleteAllButton` and `FinishPrompt` stories.
