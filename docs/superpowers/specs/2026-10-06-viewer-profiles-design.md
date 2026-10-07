# Viewer profiles: who has watched what

Design agreed 2026-10-06. Campaign: `campaigns/viewer-profiles.md`.
Records: [ADR-078](../../../decisions/architecture/2026-10-06-078-a-profile-is-a-watching-identity-held-by-the-session.md),
[UIDR-053](../../../decisions/user-interface/2026-10-06-053-a-profile-is-picked-at-the-front-door.md).
Narrows the wiki FAQ's "Why no multi-user accounts?" and amends
UIDR-012's "single-user desktop application".

## Glossary

Terms are defined here before first use and refined as the campaign
runs; they graduate to `docs/GLOSSARY.md` at completion.

| Term | Meaning |
|---|---|
| **Profile** (viewer profile) | One person who watches on this install: a row in the `profiles` table of the `MediaCentaur.Profiles` context — name, picture, hue — and the watching state below. The user-facing word is **profile**; the long form **viewer profile** is used only where a sentence would otherwise read as the social kind. Not a login: no password, no permissions. New. |
| **Social profile** | Unchanged in meaning: what the install's one social identity published about itself, `Social.Profile`, kind 12160 (ADR-073). In user-facing words always the two words; Settings → Social's "Your profile" card becomes **Social profile**; its table becomes `social_profiles`. |
| **Active profile** | The profile a browser session is being used by now, carried in the signed session cookie and read by one `on_mount` hook. A browser session is not a device concept; none is added. |
| **Picker** | The full-screen "Who's watching?" surface at `/profiles`, listing the profiles as tiles. A session with no active profile lands there; the shell's switcher returns there. Never shown while the install has one profile. |
| **Switcher** | The active profile's tile in the shell; pressing it opens the picker. |
| **Watching state** | What becomes per profile: watch progress (`library_watch_progress`), extra progress (`library_extra_progress`), track memory (`library_media_track_overrides`), watch history (`watch_history_events`), and what is derived from them — Continue Watching, resume targets, the History page, the finish prompt. |
| **Shared state** | Everything else stays one per install: the library, the TMDB store, the watchlist and its rungs, release tracking, acquisition, the social setup (identity, social profile, relays, friends, sharing toggles), every setting, integrations, the machine config. |
| **Owner profile** | The profile the phase 1 migration creates for an existing install, and the one the phase 2 migration assigns every existing watching row to: the oldest profile. Named from the social profile when one exists, else "Me"; the upgrade never prompts. |
| **Picture store** | `Profiles.PictureStore`: one 256×256 WebP per profile at `{data_dir}/images/profiles/<id>.webp`, the `Social.AvatarStore` idiom. |
| **Profile tile** | The circle that draws a profile: the picture, else the first letter of the name. The identity tile (UIDR-047) generalised to draw from three facts — name, picture URL, hue — rather than from a `Social.Person`. |

## Core idea

A profile is a watching identity and nothing more. The screen asks
who is watching; from then on, Play, resume, Continue Watching,
history and the finish prompt speak to that person. The library,
the watchlist, the social setup and the settings remain the
install's, as they are today. A single-profile install is unchanged
in every visible way.

## What exists

Nothing in the app knows who is using it. No table has a person
column. The signed session cookie (`endpoint.ex`, `store: :cookie`,
no `max_age`, so it lives for the browser session) carries only the
CSRF token. `router.ex` wraps every page in one
`live_session :default` whose `on_mount` list is the one place a
page-wide assign is injected (`ArmGesture`, `DisclosureState`,
`CapabilitiesAware`, `ShellBadges`, two `SettingAware`).

The four watching tables are keyed by the item alone:

| Table | Unique key today |
|---|---|
| `library_watch_progress` | `playable_item_id` |
| `library_extra_progress` | `extra_id` |
| `library_media_track_overrides` | `(owner_type, owner_id)` |
| `watch_history_events` | none |

`MpvSession` is registered per entity, writes progress by playable
item through `Library.Progress.record/3`, and its completion flows
`ProgressRecords.mark_completed` → `library:watch_completed` →
`WatchHistory.Recorder` → `Activities.Publisher`. Three in-memory
read models fold in watching state: `Library.Views.ContinueWatching`,
`WatchHistory.Views.Summary` with `PlaybackActivity`, and the
`Library.Progress.Worker` ETS table keyed by `playable_item_id`.

`Social.Profile` is the published profile of a key, own or a
friend's, in a table named `profiles`. The identity tile
(`Components.Social.IdentityTile`) takes a `Social.Person` and
draws the picture, the letter or the person glyph; the picture is
cropped by the `AvatarCrop` hook and made by
`ImageFiles.square_webp/4`; the hue is `Social.Hue`, an integer
0–359 on one oklch ring (UIDR-048).

## Design

**Amendments 2026-10-06/07 (planning and build).** (1) The owner profile is named
"Me" by the migration and carries no hue or picture; nothing reads the
social profile, since a migration cannot derive the identity's key and
a boot-time copy would need a heuristic for "never edited". Rename it
in Settings. (2) The picker's Add is an inline form on the picker
itself, not a link to Settings: with no active profile, Settings would
redirect back to the picker. (3) The cursor starts on the first tile;
the "last used" start is dropped. (4) The social card's ids and events
take a `social_` prefix with the relabel (`#social-profile-form`,
`save_social_profile`, …). (5) Five convergences from the unify pass:
`ImageFiles` picture primitives, `PictureField.consume_change/5`,
`MediaCentaur.DisplayName`, `MediaCentaurWeb.ProfileWords`,
`IdentityTile.crop_previews/1`. (6) Remove profile's line "Their
watching history goes with it." waits for phase 2, when it becomes true.
(7) The picker is a geometry-resolved `profile_picker` SHELF zone, not a
GRID: a wrapping row of tiles has no column count. (8) Settings →
Profiles is one form per concern (name, colour, picture), so Enter in
the name never submits a picture save. (9) `picture_at` is
`:utc_datetime_usec` so two saves in one second never share an
immutable URL; removal and add run in an immediate transaction.

### The Profiles context

`MediaCentaur.Profiles` is a Boundary with no deps. It owns:

- `profiles`: `id` (UUID), `name` (required, 1–50 characters, the
  social profile's cap), `picture?` (boolean; the file is at the
  derived path), `hue` (integer 0–359 or nil), `inserted_at`,
  `updated_at`.
- `Profiles.PictureStore`, the picture file per profile.
- `Profiles.Events` on `profiles:updates`: `ProfileAdded`,
  `ProfileChanged`, `ProfileRemoved`, each carrying the profile.
- The public functions: `list/0` (by `inserted_at`), `get/1`,
  `add/1`, `rename/2`, `set_picture/2` (`:keep`, `:none`, or
  `{:new, bytes}`, as `Social.save_profile/3` takes it),
  `set_hue/2`, `remove/1`, `count/0`.

`remove/1` refuses the last profile (`:last_profile`). Its watching
rows go with it through foreign keys declared `on_delete:
:delete_all` on every `profile_id` column, in the same transaction,
so no job and no listener carries a person's decision across a
crash (ADR-076 is met by the database, not by a job). The read models
rebuild on `ProfileRemoved`.

`Social.Hue` moves to `MediaCentaur.Hue` — the palette, `random/0`,
the 0–359 check — since two contexts now carry a hue and neither
may depend on the other. `Social` keeps using it under the new name.

### The session and the hook

The active profile is the `"profile_id"` key of the signed session.
One controller route sets it:

    POST /profiles/:id/activate   → put_session, redirect to return_to

A LiveView cannot write a cookie, so the picker's tiles are plain
form buttons posting to that route with the CSRF token; the input
system activates them like any button. The route refuses an unknown
id with a redirect to the picker.

`MediaCentaurWeb.Live.ProfileAware` is one `on_mount` hook added to
`live_session :default`:

1. Read `"profile_id"` from the session and resolve it with
   `Profiles.get/1`.
2. If the install has exactly one profile, that profile is active
   whatever the cookie says, and no picker exists.
3. If the cookie names no live profile and there is more than one,
   redirect to `/profiles?return_to=<current path>`.
4. Assign `:profile` and subscribe to `profiles:updates` through the
   subscribe door; a `ProfileChanged` for the active id re-assigns it
   (a rename shows in the shell at once); a `ProfileRemoved` for it
   redirects to the picker.

The picker itself lives in a second `live_session :profiles` without
the hook. `/setup` stays in `:default`: the phase 1 migration
guarantees one profile before any page mounts.

The session cookie has no `max_age`, so it ends with the browser
session: the app shell asks "Who's watching?" on each launch and
never mid-session. That is the chosen behaviour, not a side effect,
and is recorded in UIDR-053.

### The picker and the switcher

`/profiles` (`ProfilesLive`) is one surface: the question
"Who's watching?" over a row of profile tiles at the large size with
the name beneath each, and an **Add profile** tile at the end while
the count is under the cap of eight. A tile is a form button
to the activate route. The cursor starts on the profile the session
last used (the cookie, when it names a live profile), else the first.
It is a nav zone of its own in the input system (`profiles` layout).

The shell's sidebar carries the switcher: the active profile's tile
at the small size with its name, a link to `/profiles`. It is
present only when the install has more than one profile, so a
single-profile shell is unchanged.

The profile tile is the identity tile with its contract widened:
`attr :name`, `attr :picture_url`, `attr :hue`, `attr :size`, and
the social callers pass those from their `Person`. The marks stay
UIDR-047's: the picture, else the first letter of the name. The
third mark (the person glyph, for a key with no name) does not arise
for a profile, whose name is required. The story grows the profile
variations.

### Settings → Profiles

A new section, composed from the Settings kit (UIDR-041): one card
per profile — the tile, Name (text row), Picture (the upload with the
`AvatarCrop` stage, **Remove** while a picture exists; the same
recipe as the social picture, sharing its hook and
`ImageFiles.square_webp/4`), Colour (`HueSwatches` over
`MediaCentaur.Hue`), and **Remove profile** as an arm gesture
(MC0027) with the line "Their watching history goes with it." —
disabled with "The last profile can't be removed." on the last one.
An **Add profile** card closes the list. Saving is on the act
(UIDR-041 §2) except the picture, which the crop stage commits with
its own Save, as the social picture does.

Settings → Social's first card is relabelled **Social profile**;
nothing else there changes.

### Watching per profile (phase 2)

Every watching table gains `profile_id` (references `profiles`,
`on_delete: :delete_all`) and its unique key becomes
`(profile_id, …)`:

| Table | Unique key after |
|---|---|
| `library_watch_progress` | `(profile_id, playable_item_id)` |
| `library_extra_progress` | `(profile_id, extra_id)` |
| `library_media_track_overrides` | `(profile_id, owner_type, owner_id)` |
| `watch_history_events` | index on `(profile_id, completed_at)` |

The public functions that read or write these rows take the profile
first: `Library.Progress.record/4`, `get/2`, `complete/2`;
`Library.ProgressRecords.*`; `Library.list_in_progress/1`;
`Library.MediaTrackOverrides.*`; `WatchHistory.list_events/2`,
`summary/1`, `remove_event/2`. The `Library.Progress.Worker` ETS key
becomes `{profile_id, playable_item_id}`.

Playback carries the profile: `Playback.play/2` takes the active
profile's id, `Playback.Sessions.play/1` puts it in the params,
`MpvSession` keeps it for the session's life, so a switch mid-film
does not re-home the progress. Resume, next-episode and the track
policy resolve against that profile's rows. The completion broadcast
(`Playback.Events.SessionEnded`, MC0012) and `{:watch_completed, …}`
on `library:watch_completed` carry `profile_id`;
`WatchHistory.Recorder` writes it. `Activities.Publisher` ignores it:
every profile's completion publishes under the install's one
identity while `share_watched` is on (Decisions made, 2026-10-06).

The finish prompt (UIDR-052) opens only in sessions whose active
profile is the one that watched: `TitleDetailHost.Finish` compares
the `SessionEnded`'s `profile_id` with the socket's.

The read models key their rows by profile and read by profile:
`Library.Views.ContinueWatching.read/1` and the Home shelf, the hero
candidates' "continue" rows, `WatchHistory.Views.Summary` and
`PlaybackActivity` for the History page. A rebuild is whole, as
today — a household is a handful of profiles — and the derived
topics' messages are unchanged; a page re-reads for its own profile.
`DetailItem` keeps leaving progress out; the overlay sites
(`Progress.get/2`, the resume target, the hairline) take the socket's
profile.

Status page counts (items in progress, hours watched) are
install-wide and sum across profiles.

### Events and topics

`profiles:updates` is a source topic declared in `MediaCentaur.Topics`
with the three structs above (ADR-060). `Playback.Events.SessionEnded`
and `PlaybackStateChanged` gain `profile_id`; subscribers map-match.

### Contexts and Boundary

| Context | Change |
|---|---|
| `Profiles` | New; no deps. |
| `Library`, `WatchHistory` | `profile_id` columns and function arguments; no new dep (a column is not a dependency, and the cascade is the database's). |
| `Playback` | `profile_id` in params, session and events. |
| `Social` | `profiles` table → `social_profiles`; `Hue` → `MediaCentaur.Hue`. Nothing else. |
| Web | `Live.ProfileAware`, `ProfilesLive`, `ProfileController`, the switcher in `Layouts.app`, Settings → Profiles, the widened tile. |

### Migration

Phase 1, one schema migration: create `profiles`; insert the owner
profile when the table is empty — name from `social_profiles` for
the identity's pubkey when a row exists, else "Me"; hue from the
same row; no picture. Rename `profiles` → `social_profiles` first,
in the same migration, before the new table is created. A fresh
install gets its owner profile the same way, so `/setup` mounts with
one.

Phase 2, one schema migration per table: add `profile_id` nullable;
inline heal `UPDATE … SET profile_id = (SELECT id FROM profiles ORDER
BY inserted_at LIMIT 1) WHERE profile_id IS NULL` (the MC0015
per-line carve-out, as `DropWatchlistFlatColumns` did); then
`NOT NULL`, the foreign key and the new unique index. The heal is in
the schema migration because schema migrations run before data
migrations and a skipped-release upgrade must not reach `NOT NULL`
first. The showcase seeder (`mix seed.showcase`) creates its
progress rows under the owner profile.

### Errors

- Add with a blank name or one over 50 characters: `:name_required`
  / `:name_too_long`, the social profile's words, shown inline.
- A picture libvips cannot open: refused with a flash, as the social
  picture is. Over the 10 MB upload cap: the upload's own error.
- Remove the last profile: `:last_profile`; the button is disabled
  with the line above, so the error is a guard, not a surface.
- Activate an unknown id: redirect to the picker.
- A session whose profile was removed from another session: the
  hook's redirect, no flash — the picker is the explanation.
- More than eight profiles: `:too_many_profiles`; Add is absent at
  the cap.

### Testing

- `Profiles` context tests: add, rename, picture, hue, remove, the
  last-profile guard, the cascade (phase 2), the events.
- `ProfileAware` tests: one profile → no picker; two → redirect
  without a cookie; a removed active profile → redirect; a rename →
  re-assign. `Plug.Test.init_test_session(conn, %{"profile_id" =>
  id})` is the way a LiveView test picks a profile; `ConnCase` gains
  `with_profile/2` for it.
- Phase 2: for every function that takes a profile, a test with two
  profiles proving one's rows are invisible to the other — progress,
  resume, Continue Watching, history, track memory, the finish
  prompt.
- Factories: `profile_factory`; the progress, extra-progress,
  override and history factories build a profile by default.
- Stories: the widened tile's variations, the Settings → Profiles
  card, the picker tile (MC0009).
- Page smoke tests for `/profiles` and Settings → Profiles.
- Generic names throughout (`Sample Show`); no real people's names
  in fixtures.

## Scope

In: the context, the picture store, the session route and hook, the
picker, the switcher, Settings → Profiles, the widened tile, the
table rename and the relabelled card (phase 1); the four tables, the
progress worker, the read models, playback, the finish prompt, the
factories and the showcase seeder (phase 2); FAQ, README, wiki,
Settings reference, UIDR-012 amendment (phase 3).

Out, each on its own later decision: a few settings per profile;
watching together per title (phase 2's only obligation: a title's
progress can be shared by several profiles, which per-profile rows
with a fanned-out write satisfy); restricted profiles (a content
ceiling and a PIN — the hook and the projections' read-time filters
are the seams); any per-device concept; any per-profile social or
watchlist (declined 2026-10-06; the social relay design is revisited
separately).

## Acceptance

- With one profile, every page, test and screenshot is unchanged;
  no picker, no switcher.
- An upgraded install has one owner profile named from its social
  profile, with no prompt.
- A second profile can be added, picked, switched to, renamed,
  given a picture and a colour, and removed, from the couch with the
  gamepad alone.
- After phase 2, two profiles' progress, resume, Continue Watching,
  history, track memory and finish prompts do not leak into each
  other; removing a profile removes its rows; a film started under
  one profile keeps recording to it after the session switches.
- Friends see every profile's completions as the install's, as today.
- `mix precommit` clean; `mix context_map --check` clean.

## Build order

1. **Phase 1 — Profiles, picker, session.** `Profiles` context and
   migration; `MediaCentaur.Hue`; the widened tile and its story; the
   activate route and `ProfileAware`; `ProfilesLive`; the switcher;
   Settings → Profiles; the Social relabel. Ships with every watching
   row still shared: two profiles behave as one until phase 2, which
   the release notes say.
2. **Phase 2 — Watching per profile.** The four migrations; the
   `Library` and `WatchHistory` signatures; the worker key; playback
   params, session and events; the read models; the finish prompt;
   the factories; the showcase seeder.
3. **Phase 3 — Docs.** FAQ and README narrowed, wiki page *Profiles*,
   Settings reference, UIDR-012 amended, screenshots.
