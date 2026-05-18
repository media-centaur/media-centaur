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

* [`component-contracts.md`](component-contracts.md) — every
  LiveView function component declares a typed contract for
  domain-data attrs; eliminate bare `:any` / `:map` / `:list`.

## Archived

* [`done/page-redistribution.md`](done/page-redistribution.md) — IA
  refactor splitting Library into Home / Library / Upcoming /
  History; sidebar gains Watch (frontstage) and System
  (backstage) groups. All four pages and the sidebar split shipped
  2026-05-10. Outstanding storybook stories for the new sidebar
  grouping + History rewatch baseline re-homed to
  [`component-contracts.md`](component-contracts.md).
* [`done/pursuits-maturation.md`](done/pursuits-maturation.md) —
  three-phase maturation of the Acquisition Pursuits aggregate:
  Recipe value object + timeline VM, AutoCancel auto-pivot on
  zero-seeders, single typed PubSub dialect on `acquisition:updates`
  (`Acquisition.TargetEvents.*`). All phases shipped 2026-05-14.
* [`done/desktop-rearchitecture.md`](done/desktop-rearchitecture.md)
  — local-only, single-user, no-auth desktop paradigm shift backed
  by ADR-041 three-pillar segregation. Shipped: Library projections
  fanning out to every LiveView read path
  (`no_db_on_render_test` enforcing the budget), Acquisition split
  per ADR-043, the two grey-area Pillar-1 fields explicitly
  confirmed durable, Cache.Worker + Topics pattern documented in
  canonical moduledocs, ContinueWatching availability gap closed.
  ADR-047 (PlayableItem reification) and the `docs/architecture.md`
  Pillar-2 principle landed at closure. Workstreams A–D all
  complete 2026-05-17; closure pass 2026-05-17. Deferred items
  re-homed to test-infra (baselines), component-contracts (typed
  attrs + storybook coverage), and UX backlog (v0.62.3 empty-state
  follow-ups) — see the campaign's Closure section.
* [`done/library-presence-unification.md`](done/library-presence-unification.md)
  — moved file-presence ownership into Library
  (`Library.FilePresence`), shrunk Watcher to a thin filesystem
  observer with no durable state. Closed the orphan-stuck-pipeline
  bug class structurally. Shipped v0.65.0; follow-up FK drop
  shipped v0.65.1 (ADR-046).
* [`done/library-schema-v2.md`](done/library-schema-v2.md) —
  pre-public architectural refit of the Library bounded context:
  PlayableItem reified as the canonical leaf, supporting tables
  collapsed to single-FK or single-discriminator shapes, all
  Pillar-1 fields typed, ADR-041 projections fan out to every
  Library LiveView read path. Phases 1–3.2 shipped 2026-05-15
  through 2026-05-17; closure pass 2026-05-17. Deferred items
  re-homed to component-contracts, test-infra, and Playback
  workstreams (see the campaign's Closure section).
