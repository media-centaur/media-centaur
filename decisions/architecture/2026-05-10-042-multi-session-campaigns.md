---
status: accepted
date: 2026-05-10
amended: 2026-08-05
---
# Multi-session campaigns: tracked markdown per long-running initiative

## Context and Problem Statement

Some initiatives span many sessions and commits. Decision records capture a decision at a point in time and are not progress journals; commit messages describe one change; scratch directories and user-local plans do not survive a fresh context or a second contributor. Nothing durable answered "what is this initiative doing, what was decided, what is next, and how do we know it is done".

## Decision Outcome

1. **`campaigns/` holds one tracked markdown file per long-running initiative.** A file is warranted only when the work spans three or more sessions, has a definable end state, and carries context a fresh agent needs to resume. Single-commit features and open-ended maintenance do not qualify.
2. **Format.** Kebab-case filename without a date prefix; frontmatter `status` (`planning`, `in-progress`, `parked`, `complete`, `abandoned`, nothing else), `started`, `last_updated`; sections in order Goal, Status, Decisions made (append-only, dated), Next steps (freely edited), Completion criteria, optional Pointers. `campaigns/template.md` is the starter.
3. **The reconciliation rule.** When a campaign resumes, the first action is to read the file, reconcile it against `git log` and the current code, and update Status, Decisions and Next steps before writing any new code. A drifted file misleads; reconciliation at entry is the only guard.
4. **Lifecycle.** Create at the start, often beside the ADR whose decision the campaign enacts; update at the start and end of every session; remove the file when status becomes `complete` or `abandoned`. Git history is the archive (amended 2026-05-23; a `campaigns/done/` archive was tried and retired). Keep `campaigns/README.md` in sync in the same commit that adds or removes a file.
5. **Never link a campaign from a permanent document** (amended 2026-08-05). Decision records and specs outlive campaigns, so a markdown link is a future dead link. Name the file in backticks with "(completed and removed — see git history)".

### Consequences

* One more surface to keep in sync; without the reconciliation rule the file is worse than none.
* The campaign-worthy line is a judgment call; bias toward not creating a file unless all three criteria clearly hold.

## Amendment 2026-11-05 — campaign files are local, not committed

The owner decided that campaign files stay out of version control. They
record the reasoning behind a rollout, and a public repository is not where
that reasoning belongs; a local copy beside the code, lost with the disk,
is the accepted trade. The consequences for the convention above:

* `campaigns/` is gitignored. Nothing under it is staged, committed or
  pushed; an agent that would touch it in a commit stops.
* Closing a campaign no longer deletes its file — git history is no longer
  the archive. A closed file moves to `campaigns/retired/`, and the index's
  retired paragraph is written as before.
* Permanent documents name a campaign in backticks and never link the
  file, as the convention already asked; the file is not in the tree at
  all now.
* The campaign files committed before this date remain in the published
  history. Removing them from it would rewrite public history; that is
  the owner's call, not covered by this amendment.
