# Campaigns

Multi-session work — initiatives that span many commits with
context worth preserving across sessions and contributors. One
markdown per campaign, **removed when complete** — git history is the
archive (see ADR-042's 2026-05-23 amendment).

See [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
for the full convention. The short version:

* **When**: spans 3+ sessions, has a definable end state, carries
  resumable context. Single-commit features don't qualify.
* **Format**: kebab-case filename, frontmatter with `status` /
  `started` / `last_updated`, sections **Goal / Status /
  Decisions made / Next steps / Completion criteria**.
* **Reconciliation rule**: when resuming a campaign, read the
  file, reconcile against `git log` and the code, update before
  writing any new code. Drift makes the file worse than nothing.

Use [`template.md`](template.md) as a starter.

## Active

* [`macos-platform-support.md`](macos-platform-support.md) —
  resumed at Phase 5 (macOS impls). Seven Platform.* seams landed
  on the Linux side; CI matrix on both OSes is green and strict
  (`--warnings-as-errors`). Next up: `Autostart.Launchd`,
  `DriveProbe.BsdDf`, `LogSource.Files`, darwin-arm64 in
  `ReleaseArtifact`.
* [`test-isolation-hardening.md`](test-isolation-hardening.md) —
  **shipped 2026-05-21.** Categories A/B/D/E closed; C/F
  watching brief. `MC0018 NoDbInOnExit` Credo check enforces
  Category A mechanically. `DataCase` snapshot+drain pattern
  isolates `:persistent_term` and Task.Supervisor children.
  Will be removed (git history is the archive) after the
  macos-platform-support Phase 5 push sequence proves CI stability
  through its commits.
