---
status: in-progress
started: 2026-09-14
last_updated: 2026-09-14
---
# The title detail modal resolves its subject by TMDB identity

## Glossary

Existing terms are in [`docs/GLOSSARY.md`](../docs/GLOSSARY.md): *title*
(the `TMDB.Title` snapshot), *title detail modal*, *bookmark*, *rung*,
*title intent*, *tracked title*, *capability*. This campaign adds:

* **Deep link** — the URL that opens the title detail modal on a page that
  hosts it: `?title=<media_type>-<tmdb_id>` on `/discovery/*` and
  `/incoming`, parsed by `MediaCentaurWeb.TitleRef`. The industry term; the
  code says *title param*.
* **Known title** — a title the hosting page can produce a snapshot for from
  its own rows: a watchlist row, a feed activity, a tracked title, an omnibox
  result, the plan's subject. `TitleDetailHost.resolve_title/3` returning
  `{title, facts}` is the contract; nil means unknown.
* **Host facts** — what only the page knows about a title beyond the
  snapshot: feed provenance (sender, note, activity id), friend activity, the
  watchlist note. The second element `resolve_title/3` returns; empty for a
  title the page does not know.
* **Fetched snapshot** — a `TMDB.Title` built from the TMDB detail payload
  (`get_movie` / `get_tv`) rather than carried by a page row. The snapshot a
  deep link to an unknown title opens from.

## Goal

The modal's subject is a TMDB identity, and today it is held open only by
page membership: on every tracking broadcast the host re-resolves the open
title through the page's rows, and a title the page no longer lists closes
the modal. Two consequences the owner named as hostile on 2026-09-14: the
bookmark on a title you listed yourself removes it *and* closes the modal,
so the toggle's own undo is gone (a title with friend activity stays open,
which is why the existing test is green); and a deep link works only for a
title the receiving page already knows, so UIDR-035's "the URL is shareable"
is true only between installs with the same lists. When this is done, an
open modal stays open through any change to the lists beneath it, and a deep
link to any TMDB title opens the modal, from the page's rows when it knows
the title and from TMDB when it does not.

## Status

**Campaign opened 2026-09-14.** Diagnosis done; a throwaway test reproduced
the own-listed close on Discovery (removed again, the tree is clean). Phase 1
next.

## Decisions made

* `2026-09-14` — The bookmark keeps removing at any rung, with no confirm
  and no undo toast: a toggle removing on click is the idiom, the pressed
  state carries the meaning, and the spec of the same day deferred the toast
  deliberately. What changes is that the modal stays, so the toggle is its
  own undo. (spec `docs/superpowers/specs/2026-09-14-tracking-controls-design.md`,
  "Diff against the code" item 3)
* `2026-09-14` — An open detail keeps its own snapshot. `refresh_title_detail/1`
  asks the page for host facts and rebuilds from the detail's `title` when
  the page no longer knows it; it never closes. Closing stays with explicit
  acts (the URL losing `?title`, an own activity deleted, an auto-select
  download landing). The fresh-open rule "an unknown ref stays closed" is
  replaced in Phase 2, not widened in Phase 1.
* `2026-09-14` — A deep link to an unknown title fetches the detail from
  TMDB asynchronously and opens the modal when it lands. Nothing is shown
  while it runs; on failure a flash states the diagnosed reason (TMDB not
  set up; TMDB has no such title) and the URL is patched back to the tab.
  The page's rows stay the first source: they carry host facts a fetch
  cannot.
* `2026-09-14` — The fetched snapshot is built by the same normalisers that
  turn a search hit into a `Title` (`TMDB.TitleSearch`), exposed for a
  detail payload; no second field mapping.

## Next steps

1. **Phase 1 — the bookmark keeps the modal open.** Test first: on
   Discovery, list a movie with no friend activity, open it, click the
   bookmark, assert the modal is still open with the bookmark outline and
   `phx-value-choice='list'`, then click again and assert it is listed. On
   Incoming, the same for a title opened from Coming up. Then
   `refresh_title_detail/1` rebuilds from the detail's own title with empty
   host facts when `resolve_title/3` returns nil. Correct the
   `TitleDetailHost` moduledoc ("Closes it when the page no longer knows the
   title") and the stale `EntityModal.toggle_watchlist/2` doc that still says
   Follow and above are not toggled off.
2. **Phase 2 — a deep link opens any TMDB title.** Test first, both hosts:
   `?title=movie-<id>` for a title in no list and not in the database, TMDB
   ready, stubbed detail → the modal opens after the async lands, bookmark
   outline, Download present under acquisition; TMDB not ready → no modal,
   a flash naming the prerequisite, URL patched back; TMDB 404 → the same
   with the not-found reason; a patch to another ref or a close while the
   fetch runs cancels it. Then: expose the detail-payload normaliser in
   `TitleSearch`; in `apply_title_params/3` the unknown branch starts
   `{:title_open, ref}` when `Capabilities.tmdb_ready?/0`; `handle_title_async`
   builds the detail from the fetched snapshot and starts the preview as a
   fresh open does. A known title is unaffected.
3. **Phase 3 — audit and decommission.** Owner's brief (2026-09-14): once
   the behaviour is complete, audit every part of the app whose existence
   rested on "the page must know the title" and remove what the deep link
   makes obsolete, so the capability is first-class rather than a fallback.
   The guiding question: is the page still a *snapshot* source at all, or
   only a *host facts* source, with the snapshot resolved by identity from
   the contexts that hold one (`Discovery.get_intent/2` embeds a `Title`,
   activities embed one, a tracked title carries the name, TMDB has the
   rest)? Candidates to weigh, each kept with a reason or removed:
   `resolve_title/3`'s snapshot half; `known_titles/1` on Incoming (plan
   subject and omnibox results as title sources); `title_for_param/2`'s
   page lookup for `set_rung` clicks; the "unknown ref stays closed" rule and
   its tests; Discovery's `title_friend_activity/2` beside
   `watch_row.friend_activity`; every sentence in `TitleDetailHost`'s
   moduledoc and UIDR-035 that describes page membership as the gate.
4. **Phase 4 — record and ship.** `TitleDetailHost` moduledoc (resolution
   order); dated amendment to UIDR-035 (the URL is shareable across
   installs; the modal outlives the lists); `GLOSSARY.md` *Title detail
   modal* row (add the deep link and the sources); wiki `Watchlist.md` (the
   bookmark paragraph: the modal stays open) and `FAQ.md` (linking to a
   title); CHANGELOG. Retire this file on ship.

## Completion criteria

* On Discovery and Incoming, un-bookmarking the open title leaves the modal
  open with the bookmark outline; one more click re-lists it. Pinned by a
  LiveView test per host.
* A deep link to a TMDB title in no list and not in the database opens the
  modal on both hosts when TMDB is ready; when it is not, or TMDB has no such
  title, the page flashes the reason and the URL drops the param. Pinned by
  LiveView tests.
* Refreshing a deep link after removing its title from the watchlist reopens
  the modal from TMDB rather than closing it.
* `mix precommit` clean; UIDR-035 amended; glossary, moduledocs and wiki
  updated; shipped as a minor release; this file removed.

## Pointers

* `lib/media_centaur_web/live/title_detail_host.ex` — `apply_title_params/3`,
  `refresh_title_detail/1`, `build_detail/4`, `fetch_preview/2`, the async
  clauses.
* `lib/media_centaur_web/live/discovery_live.ex` and
  `lib/media_centaur_web/live/incoming_live.ex` — the two `resolve_title/3`
  implementations.
* `lib/media_centaur/tmdb/title_search.ex` — the search-hit normalisers the
  fetched snapshot reuses.
* `lib/media_centaur_web/components/title/watchlist_toggle.ex` — the bookmark.
* `test/media_centaur_web/live/discovery_live_test.exs` "title detail modal";
  `test/media_centaur_web/live/incoming_live_test.exs`.
* [UIDR-035](../decisions/user-interface/2026-09-07-035-two-title-surfaces.md),
  [UIDR-039](../decisions/user-interface/2026-09-11-039-add-to-watchlist-then-the-tracking-controls.md),
  [UIDR-042](../decisions/user-interface/2026-09-14-042-tracking-is-the-bookmark-and-two-switches.md).
