---
status: accepted
date: 2026-05-17
---
# Cascading deletes are an application concern, not a database concern

## Context and Problem Statement

[ADR-045](2026-05-17-045-file-presence-ownership.md) first shipped `file_presence_id` as a foreign key with `on_delete: :delete_all`. SQLite has no `ALTER COLUMN`, so tightening or dropping a constraint means a table rebuild; the cascade was never the active barrier because application code already deleted dependents first; and a bug deleting a presence row outside the sweeper's drive-availability gate would have vaporised every file row for that path instead of leaving a visible orphan. Foreign-key cascades also encode inter-context coupling where Boundary cannot see it.

## Decision Outcome

1. **The application owns cascading deletes.** The database stores plain UUID references. New schema additions carry no `on_delete:` clause; cleanup ordering lives in the context function that deletes the parent.
2. **Invariants live at the changeset layer.** "No entity without a presence" is `validate_required(:file_presence_id)` on the link changesets, populated by construction by the Library write paths.
3. **The presence cascade is explicit.** `Library.AbsenceSweeper` runs the file-event cleanup first, then deletes presence rows, the same order the code used before the foreign key existed.
4. **Existing cascades move off the database as their code is touched.** No bulk migration, no deadline.

### Consequences

* The database no longer rejects an orphan; a writer that bypasses the Library entry points can leave a file row pointing at nothing. Recovery is "scan and re-stamp", not restore from backup.
* Tests that asserted a database cascade drive the cleanup function instead.
* Rule 1 has not held. The five grandfathered cascades (playable item → watched files and watch progress, extra → extra files, watched file → subtitle tracks, release-tracking item → its child tables) remain, and six more `on_delete: :delete_all` references were added in June and July 2026 (pursuit units and target units, plan units, wants, file media infos). The rule stands; the schema carries the debt.
