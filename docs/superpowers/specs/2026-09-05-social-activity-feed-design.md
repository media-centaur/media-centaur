# Social activity feed: watched and tracking events

**Status:** design, awaiting approval (2026-09-05)

Extends the social feed beyond recommendations with two more kinds of
statement — a title watched to completion, a release newly tracked — each
behind a default-off Settings toggle. This document is the greenfield
design of the affected slice, the diff against the code, and the cost.

## Glossary

| Term | Meaning |
|---|---|
| **Activity** | One signed statement by one signer about one title: "I recommended X", "I watched X", "I am tracking X". The organizing concept; a recommendation is one kind of activity. (ActivityStreams vocabulary: actor, verb, object.) |
| **Kind** | The activity's verb, and its Nostr kind number. Three kinds: `recommendation`, `watched`, `tracking`. |
| **Address** | The title the activity is about: `tmdb:<media_type>:<tmdb_id>`. One record per signer per kind per address, on the relay and in the app. |
| **Own activity** | An activity signed by this install's identity. Sent vs received is derived from the signature, never stored. |
| **Feed** | The Discovery page's list of activities, newest first: friends' (Incoming) or this install's (Yours). Today's *Recommendations* tab. |
| **Withdrawal** | A kind-5 deletion of an own activity. Works on any kind; only recommendations get a UI control for it today. |
| **Sharing toggle** | A boolean Settings entry deciding whether an act on this install is published as an activity. Recommending is always published (it is an explicit act of sharing); watching and tracking are published only when their toggle is on. |
| **Domain time** | When the person acted (`acted_at` on the row; `recommended_at` / `watched_at` / `tracked_at` on the wire). Ordering and display use it. The wire time (`created_at`) decides only which copy wins. Unchanged from the current contract. |

## Core idea

The feed is a stream of activities. A recommendation is not a special
thing with its own table, sync and translation that watched events sit
beside; it is one kind of activity, and watched and tracking are two more.
Everything the app already does for a recommendation — sign, store one per
address, publish, sync from the start on every connect, republish to a
relay that lacks it, withdraw with a tombstone — is what it does for an
activity of any kind.

## Greenfield design

### Wire

Three addressable kinds in the app's block, one deletion kind:

| Kind | Name | Address (`d`) | Content |
|---|---|---|---|
| 32160 | Recommendation | `tmdb:<type>:<id>` | `v`, `title`, `note`, `recommended_at` — unchanged |
| 32161 | Watched | `tmdb:<type>:<id>` | `v`, `title`, `watched_at`, `episode` (TV only: `season_number`, `episode_number`, `name`) |
| 32162 | Tracking | `tmdb:<type>:<id>` | `v`, `title`, `tracked_at` |
| 5 | Deletion | `a` = `<kind>:<pubkey>:tmdb:<type>:<id>` | any of the three kinds |

Addressable means the relay and the app keep the *latest* activity per
signer per kind per title. For Watched on a TV series that is "the last
episode Alice finished" — a binge of ten episodes is one feed row that
updates, not ten rows. For a movie it is the most recent viewing. Storage
on the relay stays bounded to one record per signer per kind per title,
which is what the current Deletion rule 3 already guarantees.

Watched and Tracking are statements of an act, phrased in the past tense
("watched", "started tracking"), so a friend who later stops tracking or
never rewatches has not left a false statement behind. No automatic
withdrawal on untrack.

### Storage

One table, `activities`, replacing `recommendations`:

| Column | Note |
|---|---|
| `kind` | `recommendation` \| `watched` \| `tracking` |
| `author_pubkey`, `tmdb_id`, `media_type` | with `kind`, the unique address |
| `title` | embedded `TMDB.Title`, replaced wholesale on a newer event |
| `acted_at` | domain time, generalizes `recommended_at` |
| `note` | recommendation only |
| `episode` | watched, TV only: `%{season_number, episode_number, name}` |
| `event_id`, `raw_event`, `deleted_at`, `deletion_event` | unchanged |

Unique on `(author_pubkey, kind, tmdb_id, media_type)`.

### Context

`MediaCentaur.Recommendations` becomes `MediaCentaur.Activity` (table,
topic `activity:updates`, events `Activity.Events.{Received, Sent,
Deleted}` carrying `kind`). `Translation` gains one `to_event` /
`from_event` per kind over shared address, title and time handling.
`Sync` subscribes kinds `[32160, 32161, 32162, 5]`; nothing else in it
changes. `recommend/2` stays; `watched/2` and `tracking/1` are its
siblings, each stamping after what the row holds and publishing.

### Producers

The acts happen in other contexts. Each already broadcasts, or gains a
typed event, on its own topic; `Activity` subscribes and decides whether
to publish. No context learns about Social.

| Act | Seam | Published when |
|---|---|---|
| Finished a movie or episode | `watch_history:events` `{:watch_event_created, event}` (already exists) | `share_watched` on, and the entity has a TMDB identity (`Library.ExternalIds`). Extras (`video_object`) never. |
| Started tracking a release | new `ReleaseTracking.Events.TrackingStarted{item_id, title}` on `release_tracking:updates`, broadcast from `track_item/1` when `source: :manual` | `share_tracking` on. Auto-tracked items (library scan) never — nobody acted. |

One subscriber, `Activity.Publisher` (a GenServer, because it holds
subscriptions — no other state), resolves the `TMDB.Title` snapshot and
calls `Activity.watched/2` or `Activity.tracking/1`. The snapshot for a
library entity comes from the entity's name, year and TMDB id; poster and
overview from the library record where present. The tracking item already
holds a `Title` at the seam.

Note that "started tracking" fires on every manual-source item creation,
which includes the tracking item a one-click Download creates as a side
effect: the statement is true, and the seam is one function.

### Settings

Two `BooleanSetting` modules, both default **off**, rendered as
`settings_row` toggles in the Social section under a new "Sharing" card:

| Key | Label | Description |
|---|---|---|
| `share_watched` | Share what you watch | Tells your friends when you finish a movie or an episode. |
| `share_tracking` | Share what you track | Tells your friends when you start tracking a release. |

Turning a toggle on shares acts from then on, not history. Turning it off
stops sharing; what was already published stays on the relays until
withdrawn from Yours.

### Feed

The Discovery tab is renamed **Feed**. Rows keep the `TitleRow` shape;
the lead line carries the verb:

- "Alice recommended · 2h ago" (note as secondary, as today)
- "Alice watched S02E05 · 2h ago" / "Alice watched · yesterday"
- "Alice started tracking · 3d ago"

Every row opens the title detail modal with the same verbs (Download,
Track, Add to watchlist); Delete on an own row withdraws any kind. The
tab badge counts incoming activities of every kind. A watchlist row saved
from the feed keeps its provenance as `activity_id` (renamed from
`recommendation_id`) and still shows "from Alice".

Status tile counts (`Activity.counts/0`) stay "sent / received / last
received" over all kinds.

### Relay

`social-relay` widens `acceptedKinds` to 32161 and 32162 and generalizes
address parsing to any accepted addressable kind; slot semantics are
unchanged. Older relays refuse the new kinds with `blocked: kind 32161 is
not stored by this relay`; the app logs it as today's refusal line and
nothing else breaks.

### Dev tooling

`mix social.dev` gains `watched` and `tracking` actions; `just
social-watched` / `just social-tracking` recipes drive the dev friend.

## Diff against reality

| Gap | Kind | Disposition |
|---|---|---|
| `Recommendations` context, table, topic, events are recommendation-specific | (b) one idea, would become two representations | Fix now: rename to `Activity`, add `kind`, generalize. Migration renames the table and columns and sets `kind = 'recommendation'`. |
| `Translation` hard-codes one kind, one content shape | (b) | Fix now: per-kind clauses over shared helpers. |
| `Sync` subscribes two kinds | (a) clean seam | Widen the kind list. |
| `Recommendations.delete/1` withdraws one kind | (a) | Generalize the coordinate; no new code path. |
| `WatchlistItem.recommendation_id` | (b) | Rename to `activity_id` in the same migration. |
| Watch completion has no title snapshot | (a) `watch_history:events` exists | Resolve in `Activity.Publisher`. |
| Tracking start has no typed event | (c) `{:releases_updated, ids}` is untyped and fires for many reasons | Add `ReleaseTracking.Events.TrackingStarted` (ADR-060 shape). Converting the rest of that topic to typed structs is out of scope; noted, not scheduled. |
| Relay stores two kinds | (a) single widening point (`acceptedKinds`) | social-relay release. |
| Wiki *Social* / *Social Protocol* / *Settings-Reference* | docs | Same unit of work. |

## Cost

- **App:** context rename touching ~12 modules and their tests, one
  paired migration with backfill, two settings modules, one publisher,
  one typed ReleaseTracking event, feed lead and tab rename, dev task.
  Roughly two sessions.
- **Relay:** one small release of `social-relay` (kinds list, address
  parser, tests, protocol doc). Must ship before the app release or the
  new kinds are refused until it does.
- **Not preserved:** the `recommendations` table name, the
  `recommendations:updates` topic, and `Recommendations.*` module names.
  Nothing outside this repo and the relay reads them.

## Decisions for the owner

1. **Naming:** `Activity` for the context and the concept; **Feed** for
   the tab. Alternatives: `SocialFeed`, `Statements`.
2. **Watched granularity on TV:** latest episode per series (one row that
   updates) rather than one row per episode. Recommended for the bounded
   storage and the quieter feed.
3. **Tracking trigger:** every manual-source tracking item, including the
   implicit one a one-click Download creates. Alternative: only the
   explicit Track control, which means a second seam.
4. **Kind numbers:** 32161 Watched, 32162 Tracking.
