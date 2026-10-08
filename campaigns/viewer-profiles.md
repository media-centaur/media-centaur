---
status: in-progress
started: 2026-10-05
last_updated: 2026-10-08
---
# Viewer profiles: who has watched what

## Glossary

Terms are defined here before use and are promoted to the design
spec and `docs/GLOSSARY.md` as the campaign proceeds.

| Term | Meaning |
|---|---|
| **Profile** (viewer profile) | One person who watches on this install: a row in the new `profiles` table of the `MediaCentaur.Profiles` context — name, picture, hue — and the watching state below. The user-facing word is **profile**, the industry word; the long form **viewer profile** is used only where a sentence would otherwise read as the social kind. Not a login: no password, no permissions. |
| **Social profile** | Unchanged: what the install's one social identity published about itself, `Social.Profile`, kind 12160 (ADR-073). In user-facing words it is always the two words, so Settings → Social's "Your profile" card is relabelled **Social profile**. Its table is renamed `social_profiles` to free the name. Code keeps `Social.Profile`, scoped to its context. |
| **Active profile** | The profile a browser session is being used by right now, carried in the signed session cookie. Every page reads it from one `on_mount` hook; a session with none shows the picker. A browser session is not a device concept, and none is being added. |
| **Picker** | The full-screen "Who's watching?" surface listing the profiles; shown when a session has no active profile, and reached from the shell to switch. Never shown while the install has one profile. |
| **Watching state** | The state this campaign makes per profile: watch progress, extra progress, track memory (the audio and subtitle choice remembered per title), watch history events, and what is derived from them — Continue Watching, resume targets, the History page, the finish prompt. Each such row gains a `profile_id`. |
| **Shared state** | Everything else stays one per install, as today: the library, the TMDB store, the watchlist and its rungs, release tracking, acquisition, the social setup (identity, social profile, relays, friends, sharing toggles), every setting, integrations, the machine config. |
| **Owner profile** | The profile the upgrade migration creates for an existing install and assigns every existing watching row to. Named from the social profile when there is one, else a placeholder editable in Settings; the upgrade never prompts. |
| **Watching together** | A later feature, not designed: a title marked as watched by a set of profiles, so a completion by one is a completion for all of them. Phase 2's one obligation to it is that a title's progress can be shared by several profiles — keying progress by profile and fanning the write out to each member satisfies that. |
| **Restricted profile** | A maybe, later, for small children: a profile that sees a browse-and-play app under a **content ceiling** (the highest certification it may see, on the film and the television ladders at once; a title above it or without a certification is hidden and refused by playback) with a **PIN** on a full profile guarding the way out. A courtesy fence, not access control, and the copy would say so. Nothing is built for it now; the `on_mount` hook and the projections' read-time filters are the seams it would land on. |

## Goal

Let the people who share one Media Centaur install each keep their
own watching — progress, history, Continue Watching, resume — by
picking their profile on the screen. Nothing else splits: one
library, one watchlist, one social setup, one set of settings. A
single-profile install behaves exactly as today.

This narrows two stated positions rather than reversing them: the
wiki FAQ's "Why no multi-user accounts?" and the README's "does not
… support multiple users" become "profiles for who has watched what,
no accounts". Both are rewritten when phase 1 ships.

The roadmap this serves: Media Centaur 1 was downloads and playback;
2 is social and iterative improvement of the whole; 3 may serve
other devices the user controls, streaming-like. The active profile
is browser session state so that a second device is just another
session with its own active profile.

## Status

Phase 1 built and gated on branch `viewer-profiles` (worktree
`../media-centaur-app-viewer-profiles`, 2026-10-07): fourteen tasks,
each reviewed for spec compliance and quality with the fixes landed;
`mix precommit` clean on every static gate; the suite at 8398 with
the three load flakes below passing alone. Not merged, not pushed.
Owner's visual check and merge next.

Phase 2 planned, 2026-10-08: unify pass over the slice and the plan at
`docs/superpowers/plans/2026-10-08-viewer-profiles-phase-2.md` (seven
tasks). Execution follows on the same branch in the same worktree.

**Hand-off for the next session (read before anything else).**

* The branch is in the worktree, not the main checkout. The main
  checkout still holds *uncommitted, older* copies of the planning
  docs from the session that wrote them (`docs/superpowers/specs/…`,
  `docs/superpowers/plans/…`, the two decision records,
  `decisions/README.md`, `campaigns/viewer-profiles.md`,
  `campaigns/README.md`). The branch's versions are the truth. Before
  merging, discard those copies in the main checkout
  (`git checkout -- decisions/README.md campaigns/README.md` and remove
  the untracked files) or the merge refuses to overwrite them.
* The wiki checkout has two local, unpushed commits (`5b8ca60`,
  `4f91542`): the Social profile relabel and the new Profiles section
  of the Settings reference. Push them with the release.
* A throwaway dev server config for the worktree (port 2161, its own
  SQLite file, Me and Ana) is in this session's scratchpad and will be
  gone; recreate one from `defaults/media-centaur.toml`'s three keys
  if a worktree server is needed again.
* Full runs under machine load showed an occasional `Exqlite
  "Database busy"` on a write in test setup, an `Exqlite` client-exited
  disconnect, and the two context-map tests timing out at 60 s. These
  are normal for SQLite under load, not flakes to chase (owner,
  2026-10-08): re-run the file alone and move on. The one genuine
  load-order flake, `TargetStatus`, was fixed on the branch
  (`c20bd71e`); `Jobs.PursueTarget`'s own `String.to_existing_atom`
  carries the same fragility and is untouched.
* The context map was regenerated on the branch; `verdicts.json` is
  still empty for every finding. One false positive to raise with the
  tool: the R1 foreign-write rule matches the `name` key of the
  ignore-rules map literal in `SettingsLive.mount/3` as a write to
  `Profiles.Profile.name`.
* Open for the owner: TV sizing of the picker (96 is the largest tile
  size the identity tile allows; the heading is 3xl); the uppercase
  card titles on Settings → Profiles (the kit's card title treatment
  renders a name as "ME"); the pre-existing `Friend.name_override`
  takes no name rule while `DisplayName` governs both profiles.

**Phase 2 starts from** the "What the surveys found" section below
(the four watching tables, the touch counts, the three read models,
the playback path) and the spec's "Watching per profile" section; the
backfill is an inline heal in each schema migration assigning rows to
the oldest profile.

## What the surveys found

The facts the design rests on; verified against the code on
2026-10-05.

**There is no "who" anywhere.** No table has a person column, no
plug or `on_mount` reads a session value, the signed cookie carries
only the CSRF token. `router.ex` has one `live_session :default`
wrapping every page, with an `on_mount` list (`ArmGesture`,
`DisclosureState`, `CapabilitiesAware`, `ShellBadges`, two
`SettingAware`) — the one place an active-profile assign is
injected. The endpoint is bound to loopback; the expected client
today is one browser on the host, driven from the couch (UIDR-012).

**Watching rows today, all keyed without a person:**

| Table | Unique key today |
|---|---|
| `library_watch_progress` | `playable_item_id` |
| `library_extra_progress` | `extra_id` |
| `library_media_track_overrides` | `(owner_type, owner_id)` |
| `watch_history_events` | none |

Touch counts (lib modules): progress ≈54, `MediaTrackOverrides` 15,
`WatchHistory` 6. Three in-memory read models fold in watching
state and need a profile key: `Library.Views.ContinueWatching`,
`WatchHistory.Views.Summary` and `PlaybackActivity`, and the
`Library.Progress.Worker` ETS table (keyed by `playable_item_id`
alone). Browse, Search, Detail, RecentlyAdded and HeroCandidates are
clean; consumers overlay progress at render time, and those overlay
sites take the profile.

**Playback knows no person.** `MpvSession` is registered per entity,
writes progress by playable item, and its completion flows
`ProgressRecords.mark_completed` → `WatchHistory.Recorder` →
`Activities.Publisher`. The profile id has to ride the play params,
the session struct, the progress key, the completion broadcast and
the recorder. `Activities.Publisher` keeps publishing every
completion under the install's one identity while `share_watched`
is on (Decisions made, 2026-10-06).

**Rows that stay shared although they are about a person** — the
watchlist (`title_intents`), the social tables, the fifteen
per-person preference keys in `settings_entries` (`show_apps`,
`show_social`, `auto_play_next_episode`, `card_play_button`,
`finish_prompt`, `letterboxd_links`, `library_show_card_info`,
`share_watched`, `share_watchlist`, `spoiler_free_mode`, `ui_scale`,
`watchlist_auto_remove`, `playback.tracks`, `controls.*`,
`diagnostics_seen_at`). A later phase may move a few of these keys
per profile; the inventory is here so that phase starts from it.

**Certifications are thin**, should restricted profiles ever come:
only `library_movies.content_rating` exists, from the US entry of
TMDB `release_dates`; television certifications are never fetched
(`content_ratings` is not in the TV append list, `tmdb/client.ex`)
and no series schema carries one. Browse, Search and Home rows carry
no certification. The read-time filter pattern to follow is
`Views.Browse.apply_filters/2` and `Views.Search.matches_filters?/3`.

## Design (proposed; spec to follow)

**A new bounded context, `MediaCentaur.Profiles`**, depends on
nothing: the `profiles` table (name, picture file, hue,
`inserted_at`), a picture store in `{data_dir}/images/profiles/` on
the `AvatarStore` idiom, and the events `ProfileAdded`,
`ProfileChanged`, `ProfileRemoved` on `profiles:updates`. `Library`
and `WatchHistory` declare a `Profiles` dep and take a `profile_id`
on the functions that read or write watching state; nothing reads
the active profile below the web layer and the playback session.

**The active profile is session state.** The signed cookie carries
the profile id; a controller route sets it (a LiveView cannot write
a cookie) and redirects back; the `on_mount` hook reads it into the
socket and subscribes to `profiles:updates` so a removed profile
drops the session to the picker. A session cookie with no expiry
means the app shell asks "Who's watching?" on each launch and never
mid-session. With exactly one profile the hook takes it and no
picker exists.

**Watching rows gain `profile_id`** and their unique keys become
`(profile_id, …)`. The progress worker's ETS key becomes
`{profile_id, playable_item_id}`; Continue Watching and the History
read models are keyed by profile and rebuilt for the profile whose
event arrived. The upgrade migration creates the owner profile,
backfills every row, then makes the column `NOT NULL`.

**Playback carries the profile.** `Playback.play/2` takes the active
profile; `MpvSession` keeps it for the session's life so a switch
mid-film does not re-home the progress; the completion broadcast and
`WatchHistory.Recorder` carry it. Resume and next-episode resolve
against that profile's rows.

**Settings → Profiles** composes from the Settings kit (UIDR-041):
one card per profile with name, picture (the `AvatarCrop` hook and
`ImageFiles.square_webp/4`, as the social picture does), colour
(`Components.Social.HueSwatches` over the same hue ring, UIDR-048)
and Remove (MC0027 arm gesture; removing a profile deletes its
watching rows). The picker and the shell switcher draw the same
tile as the identity tile does (UIDR-047), so a person looks the
same everywhere.

## Phases

Each phase ships on its own and leaves a working product.

1. **Profiles context, picker, session.** The table, the picture
   store, the migration that creates the owner profile, the session
   cookie and the hook, the picker and the shell switcher, Settings →
   Profiles, the social `profiles` table renamed and the Settings →
   Social card relabelled. No watching row changes yet: with every
   row still shared, two profiles behave as one, which is the
   shipped state until phase 2. Medium.
2. **Per-profile watching.** Progress, extra progress, track memory,
   history, the progress worker, Continue Watching, the History
   page, resume and next-episode, the playback session carrying the
   profile, the finish prompt, the factories. The broad mechanical
   change (≈54 modules, three read models). Large.
3. **Docs.** FAQ and README narrowed, a wiki page, Settings
   reference, screenshots.

Later, each on its own decision, not planned here:

* **Some settings per profile** — a few of the fifteen keys above
  (spoiler-free mode, autoplay, the finish prompt, the sharing
  toggles are the likely ones).
* **Watching together, per title.**
* **Restricted profiles** — television certifications end to end,
  the two ladders, the ceiling on every surface and at playback, the
  reduced shell, the PIN.

Sizing: medium. Phase 2 touches many modules but all in one
direction; phase 1 is new code beside everything that exists. Two or
three releases.

## Decisions made

* `2026-10-05` — Campaign opened in planning; no spec or ADR yet.
* `2026-10-06` — The word is **profile** (long form *viewer profile*);
  the social kind is always *social profile* in user-facing words,
  its Settings card relabelled, its table renamed. Rationale: the
  industry word for the central concept; the existing name does not
  get precedence over the coherent design. (owner)
* `2026-10-06` — The active profile is **per browser session**, in
  the signed cookie. Rationale: other devices controlled by the user
  are a planned client (Media Centaur 3), and each is its own session
  with its own active profile. (owner)
* `2026-10-06` — **Scope is who has watched what.** An earlier draft
  of this file made the watchlist and the social setup per profile
  and proposed merging the profile with the social profile; the
  owner declined all three. One watchlist, one social setup, one set
  of settings, as today. The social relay design has open questions
  of its own and is revisited separately, not complicated here.
  (owner)
* `2026-10-06` — **Every profile's completions publish** as watched
  activities under the install's one identity while `share_watched`
  is on. Nothing new in Social. (owner)
* `2026-10-06` — **Watching together, per title**, is a later
  feature; phase 2 keys progress so a title's progress can be shared
  by several profiles. (owner)
* `2026-10-06` — **Restricted profiles are a maybe, later**, a
  courtesy fence for small children; nothing built for them now;
  a title with no certification would be hidden under a ceiling.
  (owner)
* `2026-10-06` — **No per-device concept.** Every setting stays
  install-wide in this campaign; a later phase may move a few keys
  per profile. (owner)
* `2026-10-06` — Spec, [ADR-078](../decisions/architecture/2026-10-06-078-a-profile-is-a-watching-identity-held-by-the-session.md)
  and [UIDR-053](../decisions/user-interface/2026-10-06-053-a-profile-is-picked-at-the-front-door.md)
  written. In them: removal cascades by foreign key, not by a job;
  the phase 2 backfill is an inline heal in the schema migration;
  `Social.Hue` becomes `MediaCentaur.Hue`; the identity tile's
  contract widens to the three drawn facts; the picker is a second
  `live_session`; a cap of eight profiles.
* `2026-10-06` — **Unify pass on phase 1** (owner approved five
  convergences): `ImageFiles` owns the picture-store primitives
  (`write_file/2`, `remove_file/1`, `url_if_present/2`) that the
  social avatar store and the profile picture store share;
  `PictureField.consume_change/5` is the one upload-to-master path
  (social avatar, app banner, profile picture); `MediaCentaur.DisplayName`
  is the one name rule; `MediaCentaurWeb.ProfileWords` the one set of
  error words; `IdentityTile.crop_previews/1` the one pair of preview
  frames. Kept and named: the tile's fill variant stays `own?`,
  meaning a person of this install. Plan amendments: the owner profile
  is "Me" (no seeding from the social profile); the picker's Add is
  inline; the social card's ids and events take a `social_` prefix.
* `2026-10-07` — Three amendments found during the phase 1 build (plan:
  `docs/superpowers/plans/2026-10-06-viewer-profiles-phase-1.md`):
  the picker is a geometry-resolved `profile_picker` SHELF zone, not a
  GRID, since a wrapping row of tiles has no column count; Settings →
  Profiles is one form per concern (name, colour, picture), so Enter
  in the name field never submits a picture save; `picture_at` is
  `:utc_datetime_usec` so two saves in one second never share an
  immutable URL, with removal and add run in an immediate transaction.

## Next steps

1. **Plan phase 2, per-profile watching** — the next session's first
   job, in a clear context. Start by reading this file's Status and
   hand-off, then the spec's "Watching per profile" section
   (`docs/superpowers/specs/2026-10-06-viewer-profiles-design.md`) and
   "What the surveys found" above. Write the plan with the
   `writing-plans` skill to
   `docs/superpowers/plans/2026-10-08-viewer-profiles-phase-2.md`,
   after a `unify_design` pass over the slice (the four watching
   tables, `Library.Progress.Worker`'s ETS key, the three read models,
   `Playback.play/2` and the session struct, the completion events
   under MC0012, `WatchHistory.Recorder`, the finish prompt, the
   factories, the showcase seeder). The backfill is an inline heal in
   each schema migration assigning rows to the oldest profile, with a
   per-line Credo carve-out only where the rule actually matches
   (UPDATE/DELETE in `execute(<string>)`). Then execute it the same way
   as phase 1: one implementer per task, spec review, quality review,
   full suite logged to a file.
2. Work on the same branch in the same worktree until the owner
   merges; if phase 1 has been merged by then, branch
   `viewer-profiles-phase-2` from main in a fresh worktree instead.
3. Owner's visual check of the picker and Settings → Profiles (TV
   sizing is open: 96 is the largest tile and the heading is 3xl) and
   the merge of phase 1 can happen before or during phase 2.

## Completion criteria

* A second profile can be added, picked, switched to and removed
  from the screen with the gamepad alone.
* Two profiles' progress, history, Continue Watching and resume do
  not leak into each other, proven by tests in `Library` and
  `WatchHistory`.
* An install upgraded from a single-profile release behaves
  identically until a second profile is added, with no prompt on
  upgrade.
* FAQ, README and the wiki say what the app now does.

## Pointers

* ADR-073 (the social profile), ADR-074 (`Social.Person`),
  ADR-041 (projections), UIDR-012 (single-screen appliance, to be
  amended for sessions), UIDR-041 (Settings kit), UIDR-047 (the
  identity tile's three marks), UIDR-048 (the hue ring).
* `lib/media_centaur_web/router.ex` (`live_session :default`),
  `lib/media_centaur_web/live/setting_aware.ex` (the hook to copy).
* `lib/media_centaur/playback/mpv_session.ex`,
  `lib/media_centaur/library/progress/worker.ex`,
  `lib/media_centaur/library/views/continue_watching.ex`,
  `lib/media_centaur/watch_history/recorder.ex`.
* `lib/media_centaur/social/avatar_store.ex` (the picture-store
  idiom to copy), `assets/js/hooks/avatar_crop.js`.
* For restricted profiles, if ever: `lib/media_centaur/tmdb/mapper.ex`
  (`extract_us_rating/1`), `lib/media_centaur/tmdb/client.ex` (the
  TV append list).
