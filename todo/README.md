# todo/

Self-contained task briefs, each ready to hand to a fresh Claude session (or a human) as an implementation prompt. Every file describes one discrete change with enough context — source citation, affected files, step-by-step instructions, acceptance criteria — that the reader does not need to re-run the audit or re-derive the problem.

## Conventions

- **One task per file.** If a task grows past one screen of instructions, it's probably two tasks.
- **Numeric prefix is advisory ordering only.** Not a strict dependency chain — pick the task that fits the session.
- **Start with the source citation.** Every task begins with a `Source:` line pointing back to the audit, issue, or conversation that produced it. This is how future-you verifies the task is still relevant before spending time on it.
- **Acceptance criteria are testable.** "Clean up the X code" is not a task. "Replace the eighteen `text-[Npx]` sites with a `text-micro` utility, `mix precommit` clean" is.
- **Delete on completion.** When a task ships, delete its file in the same commit as the implementation. `git log` keeps the history; the folder keeps only live work.

## Current stack (2026-04-06)

All eleven tasks below originated from the `/design-audit` run on 2026-04-06. Severities come from that audit's rubric.

| # | Task | Severity |
|---|------|----------|
| 01 | Library detail DrawerShell (or supersede UIDR-006) | Moderate |
| 02 | Micro-typography utility | Minor |
| 03 | Playback card hierarchy per UIDR-005 | Moderate |
| 04 | `items-baseline` sweep on mixed-size flex rows | Minor |
| 05 | Library initial-load skeleton | Moderate |
| 06 | Status async mount for slow data sources | Moderate |
| 07 | Console input-system coverage | Moderate |
| 08 | Console empty state | Moderate |
| 09 | Library health tiles on Status | Moderate (planned feature) |
| 10 | Auto-approve rate metric | Moderate (planned feature) |
| 11 | "Since last visit" for Recent Changes (or revise DESIGN.md) | Moderate (planned feature) |
