---
description: Run all four audits — engineering, performance, documentation, and design — and produce a combined summary.
argument-hint: "[path-or-module (optional)]"
---

# Full Audit — Engineering + Performance + Documentation + Design

Run the four audits, then combine them. All four are analysis-only; none modifies
files, and `mix precommit` is assumed green (mechanical rules are its job, not the
audits').

**Instructions:**

1. Run the four audits. They are independent, so dispatch them as parallel
   general-purpose subagents when the Agent tool is available — give each the full
   text of its command file (`.claude/commands/<name>-audit.md`) and `$ARGUMENTS`,
   and ask for the audit's complete output. Otherwise invoke `/engineering-audit`,
   `/performance-audit`, `/docs-audit`, and `/design-audit` in sequence with
   `$ARGUMENTS`. The performance and design audits may use the dev server on
   `127.0.0.1:2160` read-only; they must never run concurrently with a mutation of
   it.
2. Relay each audit's findings in full, keeping their prefixes (`E`, `P`, `D`, `DS`).
3. Print a **Combined Audit Summary**:
   - **Findings per audit:** counts by severity where the audit assigns one.
   - **Top 5 cross-cutting improvements:** issues surfaced by more than one audit, or
     with the highest overall impact. Mark items that are low-value or droppable as
     such; the user prefers a critical list over a complete one.
   - **Overall health assessment:** one paragraph across code, performance, docs,
     and design.
   - **Suggested destination for each top item:** fix now, verify on the dev server,
     or defer to a named campaign.

Output goes to the chat. The user decides what to persist or turn into board items.
