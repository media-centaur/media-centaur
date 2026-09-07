---
status: accepted
date: 2026-09-07
---
# One ladder per title: an authored rung, and machinery derived from it

Supersedes [ADR-065](2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md)
§2 (tracking reasons), §4 (seeded modes), §5 (the durable disarm) and its
collection carve-out. §1, §3, §6 and §7 stand, restated here in the
vocabulary that replaced theirs.

## Context and Problem Statement

ADR-065 established that a watchlist entry is authored and a tracked
title is derived. It then gave the derived thing a second creator and an
authored field of its own, and the consequences followed within a day.

One idea — *what should the app do about this title* — was stored twice:
presence in `watchlist_items` meant "on my list", and
`release_tracking_items.tracking_mode` meant "and this is what to do
about its releases". Two rows for one fact needed a listener
(`WatchlistListener`), a reconcile pass, a `Reasons` module to arbitrate,
and an invariant — *every active tracked title is either owned or on the
watchlist* — that a migration had to prove on real data.

It was rendered twice, too. The title detail carried a watchlist
Add/Remove control **and** a five-value tracking-mode strip, which could
contradict each other: removing from the watchlist while at Grab was a
legal click that tore the tracking down as a side effect.

The `:none` mode and the library reason existed to hold that split
together. `:none` was a durable veto against the paths that started
tracking on their own; the library reason was one of those paths. Neither
had a job once the campaign
(`campaigns/tracking-is-a-persons-act.md`) decided the app never starts
tracking a title by itself — but removing them while keeping two records
would have left permanent machinery whose only purpose is keeping two
rows agreeing about one fact.

## Decision Outcome

Chosen option: "one authored record carrying the whole ladder", because
listing a title and following its releases are not two decisions with a
relation to maintain — they are one decision at different strengths.

1. **A person holds one intent per title.** `Discovery.TitleIntent`
   (table `title_intents`, renamed from `watchlist_items`) carries the
   embedded `TMDB.Title`, its provenance, and the **rung**:

   ```
   Off        no record at all
   :list      on the list; nothing watches for releases
   :follow    keeps the calendar; releases appear under Coming up
   :ask       parks a draft plan when a release drops
   :grab      downloads it
   :default   follows the global auto-grab setting, live
   ```

2. **Off is the absence of a record, never a stored value.** That makes
   "turning tracking off deletes it" a property of the schema rather than
   a rule something has to apply — and it is why no durable disarm is
   needed. Nothing but a person can put a title on the ladder, so nothing
   can silently re-arm one.

3. **A tracked title is derived, and only derived.** It exists exactly
   while the rung follows releases *and* the title is not a film already
   in the library. It carries no authored field: no mode, no quality
   bounds, no provenance. The rule lives in one place,
   `ReleaseTracking.set_rung/3`, with `reconcile/2` re-applying it when
   the library moves underneath a rung nobody touched.

4. **`ReleaseTracking.set_rung/3` is the one write path.** It writes the
   record and derives the machinery, so the two can never disagree. It
   lives in `ReleaseTracking` rather than `Discovery` for the reason
   ADR-065 §6/§7 gave: deriving needs to see both sides, and `Discovery`
   stays free of tracking — it stores an enum and knows nothing about
   calendars, wants or grabs.

5. **The library is never a reason.** A series appearing in the library
   is a fact about the library. `LibraryLinks` links a followed title to
   the container that arrives and *unlinks* when it goes, leaving the
   rung to decide — so deleting a series from the library no longer stops
   something a person asked for. This reverses ADR-065 §2 deliberately:
   with nothing but a person able to start tracking, nothing but a person
   should stop it.

6. **Per-title download params belong to Acquisition.** Quality floor and
   ceiling and the 4K patience window move to
   `Acquisition.TitleDownloadParams`, keyed by TMDB identity. They were
   columns on the tracked title, which is why "Accept lower quality" had
   to *create one* to have somewhere to write — a person adjusting a
   quality floor started following a show.

7. **There is no collection case.** ADR-065 carved collections out
   because a tracked movie *collection* cannot be listed: its `tmdb_id`
   is a TMDB collection id, a different namespace from a film's. Their
   only writer was `ReleaseTracking.Scanner`, which had no caller
   anywhere in `lib/`; deleting it deletes the carve-out with it.

### The invariant, and why there isn't one

ADR-065's invariant was *every active tracked title is either owned or on
the watchlist*, and it had to be proven by a migration. Here the
equivalent statement is unrepresentable: a tracked title with no record
behind it cannot be produced by any code path, because the only thing
that creates one is the derivation from a record. Test factories that
want that shape must ask for it explicitly (`rung: nil`).

### Consequences

* Good, because one fact is stored once and rendered once. `Reasons`,
  `WatchlistListener`, `arm/2`, `disarm/1`, `set_tracking_mode/2`,
  `add_to_watchlist/2` and `remove_from_watchlist/2` are deleted rather
  than trimmed, along with `list_active_items/0`, `tracking_status/1` and
  three query filters that no longer have anything to exclude.
* Good, because two live bugs became impossible rather than fixed:
  "Also grab future episodes" landed titles on a mode whose grab decision
  was "off", and the gap handoff promised a search the same way.
* Bad, because a title a person follows now keeps following it after they
  delete it from the library. That is the point of (5), but it is a
  reversal of behaviour ADR-065 shipped the day before, and it belongs in
  the CHANGELOG in plain words.
* Bad, because the upgrade stops tracking every title with no record
  behind it — everything the app had started on its own. That is the
  campaign's decision, and it is the whole user-visible behaviour change.
* Bad, because the rung sits in `Discovery` while `Acquisition` reads it,
  which adds `MediaCentaur.Discovery` to Acquisition's `Boundary` deps.
  The direction stays one-way and `Discovery` still depends on nothing
  downstream.
