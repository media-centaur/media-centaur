---
status: accepted
date: 2026-07-11
---
# Merge Upcoming and Downloads into one "Incoming" page

## Context and Problem Statement

Upcoming (`/upcoming`) and Downloads (`/download`) are two thin pages telling one continuous story split at release day: tracked release (future) → pursuit + torrent (now) → history (past) → in library. Both are rarely visited, both leave large amounts of horizontal space unused, and both are always visited with the same intent — growing the collection. Even "just checking the calendar" is one click from adding something. The split forces page-jumps to follow a single release's story (Upcoming already deep-links Downloads for under-pursuit releases) and duplicates status signalling across two surfaces.

Three paradigms were mocked and compared (see `mockups/incoming-page/REASONING.md` for the winning direction's full rationale):

1. **Time Spine** — one vertical timeline: history ledger → elevated NOW band → editorial future. Calmest, but its skeleton only has slots for time-shaped content; search results, draft plans, and orphan downloads are atemporal and end up squatting in the NOW band. Its calm also inverts when the system is busiest, and its empty state is a lonely axis.
2. **Split Canvas** — demand | fulfillment panes with the seam as release day. Spends most of the canvas on a permanent calendar that the page's low visit frequency doesn't justify.
3. **Front Door Hub** — intent-first: a large add/search hero, a big-art "Coming up" shelf, subordinate operational bands. Matches the actual visit intent; time becomes a label rather than the skeleton.

## Decision Outcome

Chosen option: "Front Door Hub with the Time Spine's calm absorbed", because the merge's own justification — one rarely-visited page, always about adding — is an intent statement, and only the hub makes intent the organizing principle. The spine's qualities that made it feel calm are portable; its structural weaknesses are not.

The page is named **Incoming**, lives in the Watch nav group, and replaces both `/upcoming` and `/download` (old routes redirect). Its skeleton, top to bottom, is a strict density gradient — the spine's signature move re-expressed vertically:

* **Search hero** (most spacious) — "What would you like to add?" omnibox; titles-to-add/plan or direct release search. Results take over the space below the hero; dismissal restores the page.
* **Coming up shelf** — large poster cards, nearness-ordered, with date labels that grow more explicit further out (Tonight → Tue → Fri Jul 17 → Aug 6); season-drop stack, in-theaters watch-only, armed, and under-pursuit states as shared pill vocabulary. Calendar is a disclosure, not a resident pane. A dashed horizon terminus ("Track something to extend the forecast") closes the shelf and refocuses the omnibox.
* **In flight band** (compact, operational) — draft-plan banner, live torrent rows, searching pursuits. Chrome appears only here.
* **Recently landed ledger** — terminal history dissolving into the page floor via a mask fade, "Show earlier" disclosure, storage free-space as the ambient foot line. Full filtered history stays behind "View all history".

An under-pursuit shelf card and its torrent row are two zoom levels of one object: the card's "In pursuit · N%" pill anchors to the row, which reuses the same art, title, and pill.

Without acquisition capability the page degrades to forecast-only: in-flight band and ledger absent, hero copy reframed to tracking, and no surviving badge or caption implying grabbing is possible.

### Consequences

* Good, because one destination now serves the one intent both pages served, and the whole want → grabbing → have story is legible on a single axis.
* Good, because the leftover-space problem inverts: big shelf art and a spacious hero make slim content read as intentional, and the empty state degrades into an inviting front door rather than an empty console.
* Good, because atemporal machinery (search results, plans, orphans) has a natural home — the hub's skeleton is intent-shaped, not time-shaped.
* Bad, because time is a gradient on the shelf rather than the skeleton: releases beyond the shelf's horizon are only reachable through the calendar disclosure.
* Bad, because the same pursuit deliberately appears twice (shelf card and in-flight row); the shared-vocabulary rule must hold or the duplication reads as a bug.
* Supersedes the two-entry Watch-group arrangement that briefly placed Downloads alongside Upcoming; extends 010 (page redistribution) and 014 (media search front door).
