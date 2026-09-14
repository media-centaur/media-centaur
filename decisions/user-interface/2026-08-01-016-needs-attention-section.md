---
status: accepted
date: 2026-08-01
amended: 2026-08-02
---
# Needs attention — one problem-only section for acquisition capability faults

## Context and Problem Statement

When Prowlarr's indexers are failing or backed off, its search API still returns `200 []`, indistinguishable from an empty result: a dead VPN tunnel made the plan modal report "0 found" while releases existed. Storage and the ConnectivityBadge were already two separate problem-only surfaces on Incoming.

## Decision Outcome

1. **A blind search is never presented as a completed search.** When Prowlarr is unreachable or every enabled indexer is backed off, the gap banner says availability couldn't be checked, never "not available", and the result is not recorded as corpus knowledge.
2. **One problem-only surface** for acquisition capability faults, worst-first: Prowlarr unreachable (error), search blind (error), search degraded (warning), drive low. Amended 2026-08-02: it is a single **Heads-up glyph**, a severity-tinted triangle at the right of the zone-tab row whose details panel opens on hover, focus or click; even a quiet section was still a section.
3. **Silence is the healthy state.** Nothing renders when nothing is wrong; never a green "healthy" badge.
4. **One health backbone.** Persistent conditions feed the ADR-054 `:subsystem` incident track; the glyph renders the same assessment; the Status page is the durable record. Not a notification center: no feed, no dismiss state, no history.

### Consequences

* Indexer health is polled (30 s while the page is open, plus at search time), so a fault can be one poll stale.
