---
status: accepted
date: 2026-09-11
amended: 2026-09-24
---
# The Feed is friends' actions, one entry each

Supersedes UIDR-031 (retired); its Friends card and You card rules are carried here. Amends UIDR-036 (Ignore and the bookmark move into the entry's toolbar) and UIDR-037 (the feed has no mast). UIDR-040 (2026-09-12) is folded in.

Amended by UIDR-045 (2026-09-24): own actions join the Feed under an author scope; rules 1, 3, 4, 6 and 10 read as UIDR-045 states them, and the entry's glass card becomes a row in one list surface.

## Context and Problem Statement

The retired UIDR-031 split the social surface into Recommendations (one row per title) and Friends (one card per person), reasoning that only a recommendation is a message while watching and tracking are shelf state. With a small roster the Recommendations tab was nearly empty, and a friend listing a title, the one forward-looking act besides reviewing, was buried as a text row on their card. The row was title-first; who did what was its smallest text.

## Decision Outcome

A feed shows what changed; a profile shows what is.

### The Feed (`/discovery`, the default)

1. **Two actions.** An entry is a friend's **review** ("reviewed", the sentiment glyph when given, nothing when not) or **listing** ("wants to watch"). Watched actions stay on the Friends card; own actions on the You card; former friends' actions are not shown.
2. **One entry per action**, newest first, flat. No grouping, day dividers or re-sorting.
3. **An entry shows the friend's name, the action, and the title** (poster, name, year) plus the review text and the time. The sentence is the first line. No pennants, state markers, synopsis, type badge or avatar.
4. **Verbs and state share a toolbar** (`Discovery.FeedEntryCard`), shown only on hover or cursor, in a fixed seat so the entry's height never changes: List (bookmark; "Listed"; "Following" as a marker), Download (the one-click plan; "Downloading" or "In library" as state), Ignore (with Undo). The entry itself opens the title modal.
5. **Withdrawal removes the entry**: a deleted review, or a title dropped below List.
6. **A window, then Show older.**

### The Friends tab (`/discovery/friends`)

7. **One card per person** (`Discovery.PersonCard`), sorted by latest activity, You first. The name is the card's title; the key is a footer fact, never beside the name.
8. **The header's right side is the presence line**: the person's latest act in the feed's verbs.
9. **The body is a Recently watched strip** of up to five posters with an "all N" tile that grows in place, then *Wants to watch* and *Reviewed* text rows, Reviewed carrying the glyph. Nothing shared collapses to header and footer.
10. **The You card is the audit view of own sharing** and the only place to withdraw a broadcast. It shows what has been broadcast, never a second Watch History or Coming up.

### Consequences

* "A second friend agrees", every friend's flag on one title, leaves the feed with the pennants; it stays on the title modal and the Watchlist row.
* A friend who lists many titles produces many one-line entries.

## Anti-patterns

* **Wall of watching** — watched actions never appear as a timeline.
* **Title-first row** — reads as a list annotated with names.
* **Grouped rows** — one row per title, re-sorted on the next friend.
* **State as decoration** — badges, chips, markers or pennants on the entry body.
* **Social-network chrome** — avatars, handles, replies, reposts, reactions, counts; the npub never sits beside the name.
* **Hover jump** — a toolbar that changes the entry's height.
* **Day dividers** — the sort order is the time axis.
