---
status: accepted
date: 2026-09-11
---
# A listing replaces tracking as the shared act about wanting a title

## Context and Problem Statement

The tracking activity kind (32162) was published when release-tracking
machinery started for a title — under
[ADR-066](2026-09-07-066-one-ladder-per-title.md), when the rung first
reached Follow. A person listing a title, the act that means "I want to watch
this", told nobody. Follow and above imply List, so keeping both kinds would
put two representations of one idea on the wire, and whether a calendar is
kept is machinery, nobody else's business.

## Decision Outcome

Retire the tracking kind and publish a listing.

1. **Kind 32163, Listing**, addressable, one per signer per title. Content
   carries the title snapshot and `listed_at`. It is published when a rung
   first reaches List or above from below it (Off, Ignored or no record),
   and only while the sharing toggle is on.
2. **Dropping below List withdraws it** — a kind-5 deletion addressing the
   listing, the same tombstone path a withdrawn review takes.
3. **Kind 32162 is retired.** Numbers are never reused, so it stays in the
   protocol table marked retired; readers drop it. Stored tracking rows were
   removed by the migration that introduced the listing kind.
4. **Every surface that said tracking says listing**: bookmark for bell,
   Wants to watch on the Friends card, Share your watchlist in Settings.
5. **The relay must accept the kind before the app ships it** (`social-relay`
   v0.5.0).

### Consequences

* An installation on the old app version publishes tracking events a new
  one drops, and lists titles a new one never hears about, until it updates.
