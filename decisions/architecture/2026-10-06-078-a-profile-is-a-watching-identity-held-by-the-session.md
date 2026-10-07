---
status: accepted
date: 2026-10-06
---
# A profile is a watching identity, and the browser session holds the active one

Design: `docs/superpowers/specs/2026-10-06-viewer-profiles-design.md`. Narrows the wiki FAQ's "no multi-user accounts" and amends UIDR-012's "single-user desktop application".

## Context and Problem Statement

People who share one install share one set of watch progress, one history and one Continue Watching shelf. Nothing in the app knows who is using it: no table has a person column, the signed session cookie carries only the CSRF token, and the mpv session writes progress by playable item alone. The owner wants each person to keep their own watching, without accounts, without splitting the library, the watchlist, the social setup or the settings, and without adding a device concept the app does not have. Other devices controlled by the user are a possible future client (Media Centaur 3), so the model must not assume one browser on the host.

## Decision Outcome

Chosen option: a `Profiles` context whose rows own watching state and nothing else, with the active profile carried by the browser session.

1. **`MediaCentaur.Profiles` is a bounded context with no deps**: `profiles` (name, picture, hue), a picture store, three events on `profiles:updates`. The word is **profile**, the industry word; the social kind is always **social profile** in user-facing words, and its table is renamed `social_profiles`. Code keeps `Social.Profile`, scoped to its context.
2. **Only watching state is per profile**: `library_watch_progress`, `library_extra_progress`, `library_media_track_overrides`, `watch_history_events`, and what derives from them. Each gains `profile_id` with `on_delete: :delete_all`, so removing a profile removes its rows in one transaction — the database carries the decision, not a job. The library, the watchlist, release tracking, acquisition, the social setup and every setting stay the install's. Every profile's completion publishes under the install's one social identity while sharing is on.
3. **The active profile is browser-session state**: the `"profile_id"` key of the signed session cookie, set by one `POST /profiles/:id/activate` route, read by one `on_mount` hook in `live_session :default`. A session is not a device; no device concept is added, and `ui_scale` and the control bindings stay install-wide. A second device, if one ever comes, is another session.
4. **Playback captures the profile at play** and keeps it for the session's life; the completion events carry it. A switch mid-film does not re-home the progress.
5. **A single-profile install is unchanged**: with one profile the hook takes it, no picker and no switcher exist, and the upgrade migration creates the owner profile silently.

Declined on 2026-10-06: a per-profile watchlist, a per-profile social setup, and merging the profile with the social profile. The social relay design has open questions of its own and is revisited separately.

### Consequences

* Good, because the change is one direction — a `profile_id` on four tables and the functions over them — and the rest of the app is untouched.
* Good, because a second device is a session, not a design change.
* Good, because the cascade and the migration's inline heal keep an upgrade and a removal correct without jobs or listeners.
* Bad, because every future feature that touches watching state carries a profile argument, in code, tests and copy.
* Bad, because friends see one merged set of completions under one name; per-profile sharing waits on the social relay revisit.
* Bad, because the `profiles` table rename touches the Social context for a naming reason alone.
