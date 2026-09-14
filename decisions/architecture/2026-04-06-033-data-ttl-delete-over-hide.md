---
status: accepted
date: 2026-04-06
---
# Data has a TTL — delete over hide

## Context and Problem Statement

Features that dismiss stale data reach for a `hidden` or `dismissed` flag. Flagged rows accumulate silently, every query grows a `where hidden == false`, and a cleanup pass is eventually needed for rows that should have been deleted at dismissal.

## Decision Outcome

Records exist only while they are useful.

1. Delete, don't flag. No `hidden`, `dismissed`, `archived`, or `soft_delete` columns. If a record matters for audit, log it before deleting; do not keep the row.
2. Every table has a TTL story: when does a row stop being useful, and what removes it? "Never" or "nothing" is a design smell.
3. Periodic cleanup is defence in depth. Rows that age out naturally are swept on a schedule (the search corpus prunes stale candidates after its retention window; the retention policies do the same for events and history).
4. Removing a tree of records is ordered explicitly in application code, per [ADR-046](2026-05-17-046-app-owned-cascading-deletes.md).

### Consequences

* A dismissed record the system can legitimately re-derive (a calendar release the refresher recreates) reappears; the surface that shows it filters on a durable fact, never on a flag.
