---
status: accepted
date: 2026-09-06
---
# Friends carry the shelves; the feed is recommendations

## Context and Problem Statement

The Discovery Feed (v1.10.0) interleaved every activity kind — a
friend's recommendation, the last episode they finished, a release they
started tracking — as one newest-first timeline, split by an
Incoming/Yours switch that forgot itself on every mount. Two friends
with watched-sharing on would bury recommendations under episode rows.
The first fix on the table was a persistent filter row (direction,
kind). It managed the volume instead of removing its cause.

The cause is a projection mismatch. All three kinds are addressable on
the wire: one record per signer per kind per title, replaced by a newer
event. Watched and tracking are therefore the *current state of a
friend's shelves*, not a stream of events; only a recommendation, with
its note and sentiment, is a message. A feed shows what changed; a
profile shows what is.

## Decision Outcome

Chosen option: two projections, no filters.

* **Recommendations** (`/discovery`, the page's default) lists friends'
  recommendations only, **one row per title**, placed by its newest
  recommendation. The lead names every recommender ("Bob, Cleo · 2d
  ago"), the mast flies a named pennant per friend, and several notes
  become a short attributed list. The Incoming/Yours switch is gone.
* **Friends** (`/discovery/friends`) is one card per person, sorted by
  latest activity, **You first**. The friend's name is the card's
  title; the key is a footer fact beside the added date and Remove
  friend. The header's right side is the presence line — the person's
  latest activity of any kind with the feed's verbs ("watched S02E05 of
  Sample Show · 2h ago"). The body is a *Recently watched* strip of up
  to five posters plus an "all N" tile that grows the strip in place,
  then Tracking and Recommended as text rows, Recommended carrying the
  Like/Love sentiment. A friend with nothing shared collapses to header
  and footer.
* **The You card** is the audit view for own sharing — what friends see
  about you — and the place to reach an own activity to withdraw it.
  It never duplicates Watch History or Coming up: it shows only what has
  been broadcast.
* Every title on either surface opens the house title modal (UIDR-017),
  where every verb lives.

Nothing changes on the wire or in storage; this is a projection of the
records the app already keeps.

### Consequences

* Good, because recommendations stay visible under any volume of
  watching, and a friend's watching reads as "what Bob is into" instead
  of a wall of rows.
* Good, because the persistent-filter design and the scope switch are
  both unnecessary; there is nothing left to filter.
* Good, because the per-friend page, when the roster outgrows inline
  cards, already has its entry ("all N") and its shape (the card).
* Bad, because a title's row re-sorts to the top when a second friend
  recommends it — the new signal is "Cleo agrees", but a row already
  skimmed reappears.
* Bad, because the tab was renamed Recommendations → Feed one release
  ago and now renames back; the name follows the content.

## Anti-patterns this record names

* **Wall of watching** — watched rows never appear as a timeline.
* **Social-network mechanics** — no reactions, replies or threads beyond
  the existing Like/Love on a recommendation.
* **Key as identity** — the npub never sits beside the name.
* **Second Watch History** — the You card shows broadcast state only.
* **Pennants on posters** — sentiment stays on text rows.
