---
status: accepted
date: 2026-09-12
---
# A review replaces the recommendation as the shared opinion about a title

## Context and Problem Statement

Three activity kinds cross the wire: a recommendation (32160), a title
watched (32161), a title listed (32163). The recommendation carried a
sentiment of like or love — absent meaning like — and an optional note:
advice with a positive floor. A person who thought less of a title, or had
something to say without a verdict, had nothing to send.

The owner asked for reviews: an optional sentiment of thumbs down, thumbs
up or heart, and optional text, neither required.

Widening the sentiment on kind 32160 would change what an absent sentiment
means (like → none) and what the message claims (advice → opinion). The
protocol ([`docs/social-protocol.md`](../../docs/social-protocol.md)) says a
change of meaning bumps `v`; a reader that meets a version it does not know
drops the message, and a new reader would carry a v1 parse path beside v2 —
two representations of one idea under one kind number.

## Decision Outcome

Chosen option: "retire the recommendation kind and publish a review",
because the claim changes, not one field. The shape follows
[ADR-067](2026-09-11-067-listing-replaces-tracking-on-the-wire.md).

1. **Kind 32164, Review**, addressable, one per signer per title. Content
   carries the title snapshot, `sentiment` (`dislike` / `like` / `love`;
   absent means none), `text` (up to 500 characters, or null) and
   `reviewed_at`. A review is an explicit act and is always published,
   never behind a sharing toggle.
2. **Kind 32160 is retired.** Numbers are never reused, so it stays in the
   protocol table marked retired; relays refuse it, readers drop it.
   Stored recommendation rows — sent and received — are removed by the
   data migration that ships with the review kind: the app no longer reads
   the kind, and a friend's signed recommendation cannot be re-signed as a
   review by anyone but that friend. People review again.
3. **The sentiment's absence is a real state**: nil on the row and off the
   wire. The column is nullable with no default, and nil on every other
   kind's row too — the old column's not-null default of `like`, which
   the other kinds carried without reading, is gone with it.
4. **Every surface that said recommend says review**: the control, the
   modal, the Feed's verb, the Friends card's shelf, the pennant's
   tooltips, the Settings and Status copy, the dev friend's command. What
   an opinion of any valence looks like is
   [UIDR-040](../user-interface/2026-09-12-040-a-review-is-an-opinion-of-any-valence.md).
5. **The relay must accept the kind** before the app ships it —
   `social-relay` v0.6.0, as v0.5.0 had to for 32163.

### Consequences

* Good, because a friend's opinion of any valence is one statement, said
  once, and "nothing" on a surface now means nothing rather than a hidden
  like.
* Good, because one sentiment column with three values and a true null
  replaces a not-null default nobody read.
* Bad, because it is a wire change with a relay release in front of it, a
  protocol document change, and a migration that removes every stored
  recommendation — on the owner's install nine of their own, six with
  notes, and two from friends.
* Bad, because an installation on the old app version publishes
  recommendations a new one drops, and cannot read reviews, until it
  updates.
