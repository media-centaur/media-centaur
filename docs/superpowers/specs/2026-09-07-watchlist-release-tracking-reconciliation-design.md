# Watchlist and release tracking: one intent, one machine

**Date:** 2026-09-07
**Status:** design agreed, not implemented
**Campaign:** `campaigns/watchlist-and-release-tracking.md`

## Glossary

Terms as this design uses them. Elevated to `docs/GLOSSARY.md` at completion.

| Term | Meaning |
|---|---|
| **Watchlist entry** | A person's authored record that they want to watch one title. `Discovery.WatchlistItem`, table `watchlist_items`. Added by a person, removed by a person, never by the system. Carries the embedded `TMDB.Title`, provenance (`:manual`/`:friend`, `note`, `activity_id`). Library presence is derived, never a membership rule. |
| **Tracked title** | A title whose TMDB release calendar the app maintains. `ReleaseTracking.Item`, table `release_tracking_items`. Not authored — it exists while a **tracking reason** holds. |
| **Tracking reason** | Why a title is tracked. Exactly two, and not equivalent: the **library reason** (an owned, active container — a *default*, which evaporates with its cause) and the **watchlist reason** (a person armed a watchlist entry — an *act*, which outlives the library). |
| **Tracking mode** | What the app does about a tracked title: **None**, **Watch**, **Ask**, **Grab**, or **Global** (follow the global default until explicitly set). One field on the tracked title, replacing today's `Item.status` and `Item.auto_grab_mode`. |
| **Arming** | Raising a title's tracking mode above None. A **watchlist act**: arming a title puts it on the watchlist, wherever the control was operated from. |
| **Coming up** | The schedule projection over every tracked title with a dated release. Unchanged in kind by this design. |

## The problem

Two contexts hold overlapping records for the same idea, and three UI surfaces
render it with three vocabularies.

`Discovery.WatchlistItem` — identity `(tmdb_id, media_type)`, an embedded
`TMDB.Title`, provenance, a note. Nothing reads it but the UI:
`lib/media_centaur/discovery/` is three files. It is inert storage.

`ReleaseTracking.Item` — identity `(tmdb_id, media_type)`, denormalized title
columns, a stored library-container pair, refresh cadence, per-title auto-grab
preferences, `has_many :releases, :events`. It runs: Scanner, Refresher, Wants,
AutoTrack, the drop planner.

The collision is the manual, unowned slice. `DiscoveryLive` renders both
`title_watchlist_add` and `title_track` in the same modal, and the rule dividing
primary Track from primary Download is release date (`Logic.primary/2` →
`downloadable?`). The person chooses between "remember it" and "watch for it"
with no stated difference in outcome, and one of the two has no outcome.

Four representations of one idea:

1. presence of a watchlist entry,
2. presence of a tracked title,
3. `Item.status` (`:watching` / `:ignored`) — the bell on the library detail panel,
4. `Item.auto_grab_mode` (`global` / `off` / `ask` / `all_releases`).

`Item.source` (`:library` / `:manual`) is write-once first-cause metadata with a
single reader — `release_tracking.ex:75`, deciding whether to broadcast the
social activity — and it is wrong for any title that has both causes.

Neither **watchlist** nor **tracked title** has a `docs/GLOSSARY.md` entry,
though nearly every neighbouring term does. That absence is the diagnosis.

## The model

> A watchlist entry is the intent. A tracked title is the machinery that acts on
> it. Arming is the intent saying "act".

### Reasons decide existence

The two reasons are **not** equivalent, and the design turns on the difference.

1. **Library reason — a default.** The app tracks a title because the library
   owns an active container for it. A default evaporates when its cause goes
   away.
2. **Watchlist reason — an act.** A person put the title on their watchlist and
   armed it. **Arming is a watchlist act**: choosing to track a title puts it on
   the watchlist. A tracked title with no watchlist entry is the app applying
   its default, nothing more.

A tracked title exists while at least one reason holds, **or** while it carries
an explicit disarm (below). Reasons are queried from their owners, never stored
as a denormalized set. `Item.source` is removed.

### Tracking mode decides behaviour

| Mode | Meaning | Calendar | Wants |
|---|---|---|---|
| **None** | Tracked-but-idle: the durable record of a deliberate disarm | not refreshed | none |
| **Watch** | Keep its calendar, show it on Coming up | refreshed | none |
| **Ask** | Park a draft plan when a release drops | refreshed | opened, plan parked for approval |
| **Grab** | Grab it | refreshed | opened, plan committed |
| **Global** | Follow the global auto-grab default, live | refreshed | per the global setting |

`tracking_mode` lives on the tracked title, is set only by a person (or seeded
once at creation), and is **never raised by the system**. `Global` is the only
value that changes with an ambient setting, and only while the person has never
set the mode explicitly — an explicit mode is a concrete value and is therefore
immune to a global change.

### Creation defaults

| Created by | Seeded mode | Why |
|---|---|---|
| Library scan / `AutoTrack`, on newly owning an active container | **Global** | preserves today's behaviour: the global auto-grab setting is the person's opt-in |
| A person arming a watchlist entry | **Watch** | auto-grab is opt-in; adding something to your list must never start a download |

Adding a watchlist entry is free — it creates no tracked title. Arming is a
second, deliberate act.

### An explicit disarm is durable

A tracked title whose mode a person set to **None** survives even when no reason
holds — inert: no calendar refresh, no wants, no Coming up row, invisible in
every list. It exists only so that re-acquiring or re-listing the title later
cannot silently re-arm what the person turned off. This is the strict form of
"never raised by the system".

Every other mode evaporates with its last reason, because raising is the only
direction that can surprise, and nothing here raises.

### Losing a reason

| Situation | What happens |
|---|---|
| Armed watchlist entry removed, title not owned | No reason left, the mode was raised not lowered — row deleted, tracking stops |
| Armed watchlist entry removed, title owned | Library reason holds — tracking continues at the app default |
| Library container deleted, title on the watchlist | Watchlist reason holds — **tracking continues at the mode the person set**. New releases still arrive |
| Library container deleted, no watchlist entry | The app tracked it because it was owned; it is not — row deleted, tracking stops |
| Mode set to None, then every reason lost | Row survives inert, carrying the disarm |

The third row is the case today's code gets wrong in the opposite direction:
`detach_library_containers/1` nulls the container pair and keeps *every* item,
so a deleted series keeps tracking and grabbing whether or not anyone asked.

### The invariant

> **Every *active* tracked title — mode above None — is either owned or on the
> watchlist.**

Inert None rows are exempt. This is what lets the UI retire the straggler
concept: a straggler is active-but-undated, and there is no active tracked title
without a list that shows it.

## Storage and boundaries

Two tables, each with one job — no longer two representations of one idea.

**`watchlist_items`** (Discovery) — authored membership: the embedded
`TMDB.Title`, provenance (`:manual` / `:friend`, `note`, `activity_id`). No mode
field. Unchanged in shape by this design.

**`release_tracking_items`** (ReleaseTracking) — the machinery: TMDB calendar,
releases, events, wants, refresh cadence, the denormalized `imdb_id` / `tvdb_id`
the drop planner verifies against, plus `tracking_mode` and the nullable quality
overrides that already exist. Drops `status` and `source`; `auto_grab_mode`
becomes `tracking_mode` with `off` split into None (idle) and Watch (calendar
only).

**Dependency direction stays one-way.** `ReleaseTracking` gains a
`WatchlistListener` mirroring the existing `LibraryListener`: subscribes to
`discovery:updates`, reconciles the affected title. `ReleaseTracking` deps gain
`Discovery`; `Discovery` stays free of tracking. The watchlist *view* composes
tracking state in the web layer, which the original watchlist spec already
anticipated for in-flight decoration.

**The social broadcast moves with the act.** `Events.TrackingStarted` fires from
the arming path, not from `ReleaseTracking.track_item/1` — creating a tracked
title is machinery; arming is a person's act. It stays inside `ReleaseTracking`,
because the dependency runs that way and `Discovery` must stay free of tracking;
`ReleaseTracking.arm/2` performs both halves of the act (list, then track) at the
one place that can see both sides. The `share_tracking` preference is unchanged.

## UI

### Two title surfaces, split by a fact a person can see

Today there are three, split by which table the title came from — a distinction
nobody outside the codebase can perceive. A single title walks through all three
over its life (watchlisted → tracked → downloading → owned), getting a different
modal, route and vocabulary at each step; and an owned series with an announced
season exists in two of them at once, neither showing the whole title.

| Surface | For | Gains |
|---|---|---|
| **Library detail** (`DetailPanel`, the library tenant of `CinematicShell`) | titles with files | the release timeline and the tracking-mode control, replacing the bell — a one-bit view of a five-value field |
| **Title detail** (`Discovery.TitleDetailModal` absorbing `ReleaseTracking.TitleModal`) | titles without files | the release timeline and the tracking-mode control |

The release timeline and the tracking-mode control become two shared components
mounted by both. That is the real de-duplication: one idea, rendered twice
today, in different markup with different words.

`Stop tracking` stops being a distinct verb — it is setting the mode to None.
`Remove from watchlist` becomes the separate, unrelated act it always should
have been. `Track` disappears as a verb: adding to the watchlist and arming
replace it.

### Three lists, one job each

- **Watchlist** (`/discovery/watchlist`) — authored intent, owned or not, armed
  or not. Each row shows its tracking mode and its next date when it has one.
  The arming surface.
- **Coming up** (`/incoming`) — the schedule across every tracked title,
  however it came to be tracked.
- **Library** (`/library`) — what you have.

### Retired

The **"Not scheduled yet" stragglers line** on Coming up. Its population is a
tracked title with no announced date, which under the invariant is either owned
(visible in the library, mode on its detail) or on the watchlist (visible there,
mode on its row). It exists today only because no other list showed
tracked-but-undated titles. This supersedes the straggler half of UIDR-017 and
retires `UpcomingFeed.Straggler`.

## Migration

Every phase ships a paired migration with an idempotent backfill and a CHANGELOG
mention.

1. **`auto_grab_mode` → `tracking_mode`.** `global` → Global, `ask` → Ask,
   `all_releases` → Grab. `off` → Watch (the row was refreshing its calendar).
2. **`status: :ignored` → `tracking_mode: :none`,** overriding step 1 — an
   ignored row was not refreshing, whatever its grab mode said. Drop `status`.
3. **`source: :manual` items get watchlist entries.** Without this the
   invariant fails on first reconcile and manually-tracked titles are stranded:
   they have no library reason and no watchlist reason, and would be deleted.
   Backfill a `:manual` watchlist entry from the item's title fields for every
   `source: :manual` item with no existing entry. Drop `source`.
4. **Reconcile every tracked title once** after the cutover, to prove the
   invariant on real data before the delete path is live.

## Open questions

- **Inert None rows accumulate.** One row per title a person ever deliberately
  disarmed. Bounded by deliberate acts, so small, but `Retention` should be told
  about them rather than left to discover them. Decide the policy in Phase 1:
  most likely never pruned, since pruning one silently re-arms the title, which
  is the whole thing this row exists to prevent.
- **Arming from the library detail creates a watchlist entry.** A visible
  consequence of an explicit act, and the point of "the watchlist is where you
  arm" — but it must be stated by the control's copy, not inferred. Surfaced,
  never silent.

## Decision records this warrants

- **ADR-065** — tracking reasons and the derived tracked title: the
  default-versus-act asymmetry between the two reasons, the durable disarm,
  existence from reasons, mode from a person, the invariant, and the removal of
  `Item.source`.
- **UIDR-035** — two title surfaces split by "has files", and the retirement of
  the straggler line (superseding that half of UIDR-017).
