# Campaigns

Multi-session work — initiatives that span many commits with
context worth preserving across sessions and contributors. One
markdown per campaign, archived to `done/` when complete.

See [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
for the full convention. The short version:

* **When**: spans 3+ sessions, has a definable end state, carries
  resumable context. Single-commit features don't qualify.
* **Format**: kebab-case filename, frontmatter with `status` /
  `started` / `last_updated`, sections **Goal / Status /
  Decisions made / Next steps / Completion criteria**.
* **Reconciliation rule**: when resuming a campaign, read the
  file, reconcile against `jj log` and the code, update before
  writing any new code. Drift makes the file worse than nothing.

Use [`template.md`](template.md) as a starter.

## Active

* [`desktop-rearchitecture.md`](desktop-rearchitecture.md) —
  local-only, single-user, no-auth desktop paradigm shift
  (ADR-041 three-pillar segregation as backbone). Covers
  projections, ephemeral-state cleanup, Acquisition split,
  pattern documentation.
* [`component-contracts.md`](component-contracts.md) — every
  LiveView function component declares a typed contract for
  domain-data attrs; eliminate bare `:any` / `:map` / `:list`.

## Shipped (retro story coverage outstanding)

* [`page-redistribution.md`](page-redistribution.md) — IA
  refactor splitting Library into Home / Library / Upcoming /
  History; sidebar gains Watch (frontstage) and System
  (backstage) groups. *All four pages and the sidebar split
  shipped 2026-05-10; storybook stories for the new sidebar
  grouping + History rewatch baseline remain — tracked under
  component-contracts.*

## Archived

* [`done/library-presence-unification.md`](done/library-presence-unification.md)
  — moved file-presence ownership into Library
  (`Library.FilePresence`), shrunk Watcher to a thin filesystem
  observer with no durable state. Closed the orphan-stuck-pipeline
  bug class structurally. Shipped v0.65.0; follow-up FK drop
  shipped v0.65.1 (ADR-046).
