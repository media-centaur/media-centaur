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
/ Completion criteria). Completed campaigns move to
`campaigns/done/` rather than being deleted.

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
> file, reconcile it against `jj log` and the current code, and
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
* **Archive** to `campaigns/done/` when status flips to
  `complete` or `abandoned`. Archived files are kept verbatim —
  they remain a source of historical context.

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
* `campaigns/done/desktop-rearchitecture.md` — first seeded campaign
  (ADR-041 three-pillar segregation, broader local-only desktop
  paradigm shift). Closed 2026-05-17.
