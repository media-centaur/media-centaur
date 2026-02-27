---
status: accepted
date: 2026-02-27
---
# Record architecture decisions

## Context and Problem Statement

Architectural decisions are scattered across CLAUDE.md (principles), PIPELINE.md (pipeline architecture), `../specifications/` (data contracts), `plans/` (implementation plans), and git history. There is no single place to find *why* a decision was made or what alternatives were rejected. New contributors (human or AI) must reverse-engineer rationale from code and comments.

## Decision Outcome

Chosen option: "MADR 4.0 lean template in `adrs/`", because it is the lightest structured format that captures context, decision, and consequences without ceremony.

### Consequences

* Good, because decision rationale becomes discoverable in one directory
* Good, because the lean template keeps each ADR short — easy to write and review
* Good, because existing decisions can be retroactively documented from git history and specification files
* Bad, because retroactive ADRs approximate the original decision date rather than recording it exactly
