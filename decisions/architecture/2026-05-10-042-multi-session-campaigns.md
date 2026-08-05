---
status: accepted
date: 2026-05-10
---
# Multi-session campaigns: tracked markdown per long-running initiative

## Context and Problem Statement

Several initiatives in this repo span many work sessions and many
commits — the in-memory projection rollout (ADR-041), the page
redistribution IA refactor, future cuts like the Acquisition split.
Each one accumulates context that does not fit any existing surface:

* **ADRs** capture a *decision* at a point in time. They are not
  progress journals and should not be edited as work continues.
* **Commit messages** describe a *change*. They cannot answer
  "where are we in the larger arc, and what's the next step?"
* **`/todo/`** is gitignored — intentionally, to keep an internal
  scratchpad. It does not survive collaborator handoff and is not
  visible from a fresh agent context.
* **`~/.claude/plans/`** is user-local. A new context window or a
  different machine cannot read it.

The existing surfaces solve adjacent problems but leave a gap: a
*shared, durable, scannable* record of "what is this multi-step
campaign trying to accomplish, what has been decided, what's next,
and how do we know it's done?" Without it, every context reset
costs rediscovery work, and any second contributor (human or
agent) starts blind.

## Decision Outcome

Chosen option: a tracked **`campaigns/`** directory at the repo
root, holding one markdown per long-running initiative, each
following a small template (Goal / Status / Decisions / Next steps
/ Completion criteria). Completed campaigns are **removed** from the
tree once closed; their full history remains in git.

> **Amended 2026-05-23.** Originally completed campaigns were archived
> to `campaigns/done/` rather than deleted. That directory was retired —
> finished campaigns are now removed (git history is the archive), to
> keep the working tree focused on active work.

### When a campaign warrants a file

Create a campaign file when the work:

* Spans **three or more sessions** (or three or more commits with
  meaningful gaps), AND
* Has a **definable end state** (not open-ended maintenance), AND
* Carries **context that future-you or a fresh agent will need**
  to resume cleanly (decisions made, paths not taken, in-flight
  state).

Single-commit features and ongoing maintenance work do not
warrant a campaign file — commit messages and the existing
`docs/` tree cover them.

### Format

* Filename: `kebab-case.md`. No date prefix — the file's
  frontmatter holds the started/updated dates, and unique names
  scan better in `ls`.
* Frontmatter: `status` (one of *planning, in-progress, paused,
  complete, abandoned*), `started`, `last_updated`.
* Sections (in order): **Goal**, **Status**, **Decisions made**,
  **Next steps**, **Completion criteria**, optional **Pointers**.
* Decisions section is append-only with dates. Next steps section
  is freely edited as priorities shift.
* Template lives at `campaigns/template.md`.

### The reconciliation rule

The single most important rule, because it's the failure mode
that makes any progress journal worse than nothing:

> **When a campaign resumes, the first action is to read the
> file, reconcile it against `git log` and the current code, and
> update Status / Decisions / Next steps before writing any
> new code.**

If a campaign file drifts from reality, it actively misleads.
Treating reconciliation as the entry point prevents drift from
accumulating across sessions.

### Lifecycle

* **Create** at the start of a campaign (often alongside an ADR
  that captures the *decision* the campaign *enacts*).
* **Update** at the start of each session (reconciliation rule)
  and at the end of each session (record decisions made, refresh
  next steps).
* **Remove** the file when status flips to `complete` or
  `abandoned` — git history preserves the verbatim record.
  (Amended 2026-05-23; previously archived to `campaigns/done/`.)
* **Never link a campaign from a permanent document.** Decision
  records and design specs outlive campaigns by construction, so a
  markdown link from an ADR to a campaign file is a dead link waiting
  for that campaign to ship. Name it in backticks instead —
  `` `campaigns/foo.md` (completed and removed — see git history)`` —
  which stays true either way and still tells a reader where to look.
  (Amended 2026-08-05, after two ADRs and three design specs
  accumulated dangling campaign links this way.)
* **Keep `campaigns/README.md` in sync in the same commit** that adds
  or removes a campaign file. It is the entry point CLAUDE.md points
  at; a campaign missing from it is invisible.

The `status:` frontmatter takes one of `planning`, `in-progress`,
`parked`, `complete`, `abandoned` — nothing else, so the field stays
greppable. Narrative belongs in the **Status** section, not the key.

### Consequences

* Good, because a fresh context window (or contributor) can pick
  up a multi-step initiative without rediscovery work.
* Good, because it forces explicit completion criteria up front,
  which prevents campaigns from drifting into open-ended scope.
* Good, because it gives ADRs a place to *land* operationally —
  the ADR captures the decision; the campaign captures the
  rollout.
* Bad, because it adds another doc surface to keep in sync. The
  reconciliation rule is the only guard against drift; if it
  isn't followed, the file is worse than no file.
* Bad, because the line between "campaign-worthy" and
  "single-commit feature" is judgment-call territory. Bias
  toward not creating a file unless the three criteria above
  are all clearly met.

## Pointers

* `campaigns/README.md` — index of active campaigns + the
  convention summary.
* `campaigns/template.md` — starter template.
* The first seeded campaign was `desktop-rearchitecture` (ADR-041
  three-pillar segregation, broader local-only desktop paradigm shift;
  closed 2026-05-17). It and other completed campaigns were removed per
  the 2026-05-23 amendment — see git history.
