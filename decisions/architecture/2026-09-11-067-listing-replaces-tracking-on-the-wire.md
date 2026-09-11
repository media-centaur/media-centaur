---
status: accepted
date: 2026-09-11
---
# A listing replaces tracking as the shared act about wanting a title

## Context and Problem Statement

Three activity kinds cross the wire: a recommendation (32160), a title
watched (32161), and a title tracked (32162). The third is published when
the release-tracking machinery starts for a title, which under
[ADR-066](2026-09-07-066-one-ladder-per-title.md) means the person's rung
first reached Follow. A person who puts a title on their watchlist at
List — the act that means "I want to watch this" — tells nobody.

[UIDR-038](../user-interface/2026-09-11-038-the-feed-is-friends-actions-one-entry-each.md)
needs the listing to be the shared act. Keeping tracking beside it would
put two representations of one idea on the wire: Follow and above imply
List, so every start of tracking is a listing, and whether a calendar is
being kept for the title is machinery, nobody else's business.

## Decision Outcome

Chosen option: "retire the tracking kind and publish a listing", because
one shared act about wanting a title is the whole story a friend needs.

1. **Kind 32163, Listing**, addressable, one per signer per title. Content
   carries the title snapshot and `listed_at`, when the person acted. It
   is published when a title's rung first reaches List or above from
   below it — Off, Ignored, or no record — and only while the sharing
   toggle is on.
2. **Dropping below List withdraws it**: a kind-5 deletion addressing the
   listing, the same tombstone path a withdrawn recommendation takes. The
   shelf and the feed both stop saying "wants to watch" because it is no
   longer true.
3. **Kind 32162 is retired.** Numbers are never reused, so it stays in the
   protocol table marked retired; readers drop it. Nothing publishes it
   again, and stored tracking rows are removed with the migration that
   introduces the listing kind rather than kept as a parallel shelf.
4. **Every surface that said tracking says listing.** The pennant's bell
   becomes a bookmark; the Friends card's Tracking shelf becomes Wants to
   watch; the presence line says "wants to watch Sample Show"; the
   Settings toggle Share tracking becomes Share your watchlist.
5. **The relay must accept the kind** before the app ships it, as
   `social-relay` v0.4.0 had to for 32161 and 32162.

### Consequences

* Good, because a friend's act about wanting a title is one thing, stated
  once, from the rung the person actually set.
* Good, because the volume concern goes away: a listing fires once per
  title a person deliberately lists, not on every machinery start.
* Bad, because it is a wire change with a relay release in front of it,
  a protocol document change, and a migration that drops stored tracking
  rows. That is the cost of not carrying two kinds for one idea.
* Bad, because an installation on the old app version publishes tracking
  events a new one drops, and lists titles a new one never hears about,
  until it updates.
