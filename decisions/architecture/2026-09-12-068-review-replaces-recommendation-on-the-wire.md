---
status: accepted
date: 2026-09-12
---
# A review replaces the recommendation as the shared opinion about a title

## Context and Problem Statement

The recommendation kind (32160) carried a sentiment of like or love — absent
meaning like — and an optional note: advice with a positive floor. A person
who thought less of a title, or had something to say without a verdict, had
nothing to send. Widening the sentiment in place changes what absence means
and what the message claims — a version bump and a second parse path under
one kind number.

## Decision Outcome

Retire the recommendation kind and publish a review, following the shape of
[ADR-067](2026-09-11-067-listing-replaces-tracking-on-the-wire.md).

1. **Kind 32164, Review**, addressable, one per signer per title. Content
   carries the title snapshot, `sentiment` (`dislike` / `like` / `love`;
   absent means none), `text` (up to 500 characters, or null) and
   `reviewed_at`. A review is an explicit act, always published, never behind
   a sharing toggle.
2. **Kind 32160 is retired**: marked retired in the protocol table, refused
   by relays, dropped by readers. Stored recommendation rows — sent and
   received — were removed by the data migration that shipped the review
   kind; a friend's signed recommendation cannot be re-signed as a review by
   anyone but that friend.
3. **The sentiment's absence is a real state**: nil on the row and off the
   wire; the column is nullable with no default.
4. **Every surface that said recommend says review.** How an opinion of any
   valence looks is
   [UIDR-040](../user-interface/2026-09-12-040-a-review-is-an-opinion-of-any-valence.md).
5. **The relay must accept the kind before the app ships it** (`social-relay`
   v0.6.0).

### Consequences

* An installation on the old app version publishes recommendations a new
  one drops, and cannot read reviews, until it updates.
