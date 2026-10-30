---
status: in-progress
started: 2026-10-28
last_updated: 2026-10-29
---
# Test sweep: retire tests that pin a removal or an implementation detail

## Glossary

Terms are defined here before use. The sweep's vocabulary goes to the
`automated-testing` skill when the campaign closes.

| Term | Meaning |
|---|---|
| **Pinning test** | A test whose only failing diff is reintroducing something that was deliberately removed: a class, an attribute, an element, a code path. It records a removal rather than guarding a behaviour. |
| **Implementation-detail assertion** | An assertion on markup or structure that no user and no caller observes and no contract names: a Tailwind utility class, a wrapper's shape, a selector that exists in exactly one place in `lib/` and one in `test/`. |
| **Contract hook** | A marker the app treats as a contract and may be asserted on: an `id`, `data-component`, `aria-*`, `data-nav-*`, `data-tip`, a component's own class recipe (`.sidebar-link-active`), visible copy. |
| **Behaviour test** | A test that fails when something a user or a caller can observe changes, with a failure message that names that behaviour. |
| **Red-green residue** | A test written to drive a fix (red first, per the `automated-testing` skill) whose value ended when the fix landed. The red run was the point; the test outlived it. |
| **Candidate** | A test the sweep script flags. A candidate has not been judged. |
| **Verdict** | The judgment pass's bin for a candidate: **delete** (pinning or detail with no recurrence path), **rewrite** (the intent is real, the assertion is at the wrong level; re-aimed at behaviour, or replaced by a non-automated check named in the commit), **keep** (a plausible accidental breakage exists). |
| **Sweep script** | The deterministic script that produces the candidate table from signatures. It never judges. |
| **Mutation check** | For a borderline candidate: revert its originating fix in a worktree, run the test, and read the failure as a stranger would. A failure that does not say what broke in product terms is a rewrite or a delete. |
| **Originating commit** | The commit that introduced the assertion, from `git blame`. Its message says whether the test drove a removal, a rename, or a bug fix. |

## Goal

Remove the tests that cost maintenance and give nothing back: the ones
that fail only if we reintroduce something we removed on purpose, or
that pin markup internals no contract names. A test earns its place
when a plausible future change could break the behaviour it pins by
accident and the failure would name that behaviour. The suite is about
8,750 tests; the sweep is expected to flag a few dozen, mostly in the
web layer. The pattern found most often becomes a Credo check, so the
next one is caught at precommit instead of in a review.

## Status

M1 done 2026-10-29: `scripts/test-sweep` lists 360 candidates in 145
files out of 8,091 tests. Next is M2, the judgment pass over that table.
Opened 2026-10-28 after the picker-centring fix, where a
`refute has_element?(view, "main .max-w-7xl #profile-picker")`
assertion was written to drive the fix and removed the same session as
red-green residue; the owner asked how a sweep of the whole suite would
go and then for this campaign.

## Principles

1. **The criterion is the only test of a test.** A plausible accidental
   breakage, and a failure message that names the behaviour. Nothing
   else decides a verdict: not age, not author, not file.
2. **Contract hooks are fair game; utility classes are not.** Asserting
   on an id, a `data-component`, an `aria-*` attribute or visible copy
   is a behaviour assertion. Asserting on `max-w-7xl` or `flex` is not.
3. **ADR-027 files are untouched.** Parser and pipeline regression tests
   are append-only whatever the sweep says about them.
4. **The script proposes, the owner disposes.** Every delete is ruled on
   by the owner from the candidate table. The agent recommends.
5. **Rewrite re-aims, never weakens.** A rewrite moves the assertion to
   the level a user or caller sees. It never loosens an exact match to a
   substring or drops a bound (ADR-027's rule, applied suite-wide).
6. **One commit per verdict bin**, so the deletes are reviewable on
   their own and revertable on their own.
7. **Green at every commit.** `mix precommit` passes after each bin
   lands.

## Open decisions

None.

## Decisions made

* `2026-10-28` — Opened. The criterion in Principle 1 is the campaign's
  whole basis. (This file's first commit.)
* `2026-10-28` — The sweep is two passes: a mechanical pass that only
  lists, and a judgment pass with the criterion written down. The
  passes never merge; a script that judges would encode today's taste.
* `2026-10-29` — The sweep script lives in the repo as
  `scripts/test-sweep`, on the owner's condition that it exposes none of
  their data: it reads tracked test sources and git history, writes a
  markdown table to stdout, and opens no database and no configuration.
* `2026-10-29` — A rewrite may end as no automated test when the intent
  is verified by looking (a geometric fact such as centring). The commit
  names the replacement check (a `page-shot` measurement, a storybook
  variation) and the `automated-testing` skill gains a line saying when
  that is the right outcome (M4).
* `2026-10-29` — Two calibrations of the signatures, from the first run:
  S1 skips refutes on the contract hooks Principle 2 names (ids,
  `data-nav-*`, `aria-*`, `data-component`, `data-tip`), since a refute
  on a hook is a behaviour assertion; and S5 (originating commit says
  remove/rename/…) is a column but not a candidacy test on its own,
  because almost any fix commit matches it. S1, S2 and S4 read markup
  assertions only (`has_element?`, `element(`, `=~` on rendered HTML).

## Next steps

Ordered. M1 is documentation and a check only, so it skips the
milestone procedure's steps 3–6. M3 changes the suite and runs all
seven.

1. **M1 — the sweep script.** Emits a table: file and line, the
   assertion, the signature it matched, the originating commit and its
   message. Signatures, each a separate column so a candidate can match
   several:
   * `refute has_element?` / `refute html =~` whose selector is a class
     or attribute rather than visible text;
   * assertions on Tailwind utility or layout classes (`max-w-`, `flex`,
     `hidden`, `w-36`, `gap-`), as opposed to contract hooks;
   * test names containing "no longer", "does not render", "removed",
     "old", "legacy", "still";
   * a selector that occurs once in `lib/` and once in `test/`;
   * an originating commit whose message matches "remove", "retire",
     "drop", "rename", "delete".
   Excludes `test/media_centaur/parser_test.exs` and the pipeline
   regression files (ADR-027). Re-runnable; the count is recorded here
   each time it runs.

   ✅ 2026-10-29 — `scripts/test-sweep` (an Elixir script; a row is a
   test case, each signature a column, sorted by signatures matched).
   Runs: `2026-10-29` at `d7704b57`: 360 candidates in 145 files, of
   8,091 tests in 672 files. S1 127, S2 4, S3 220 (still 132, removed 33,
   old 26, legacy 15, no longer 14), S4 18, S5 46. The S2 count says
   utility-class assertions are already rare; "still" is three fifths of
   S3 and mostly reads as behaviour ("still deletes the rest of the
   batch"), which M2 will confirm row by row rather than the script
   dropping the word.
2. **M2 — the judgment pass.** For every candidate: what diff would make
   it fail, and would we want to be stopped by that diff. Bin and a
   one-line reason. Mutation check on the borderline ones. The result is
   one table for the owner, with the delete bin first.
3. **M3 — execution.** The owner's verdicts land as one commit per bin:
   deletes, rewrites, then nothing for keeps. Each rewrite names the
   behaviour it now pins; a rewrite that ends as no automated test names
   its replacement check in the commit message.
4. **M4 — the Credo check.** The signature that produced the most
   deletes becomes a custom check in `credo_checks/` beside MC0024, with
   its moduledoc carrying the criterion. The `automated-testing` skill
   gets one paragraph: when a red test is residue and comes out with the
   fix.

## Completion criteria

* The sweep script runs clean on `main`: every remaining candidate has
  a recorded **keep** verdict and reason, or no longer matches.
* Every delete and rewrite is in a commit that names its bin, and
  `mix precommit` passed on each.
* The Credo check from M4 is in `.credo.exs` and fails on the pattern
  that was deleted most.
* The `automated-testing` skill says when a red-first test is residue,
  and this file's glossary terms that outlive it are there.
* ADR-027's files are byte-identical to where they were when the
  campaign opened.

## Pointers

* `scripts/test-sweep` — the sweep script (M1); its header is the
  signature list as implemented.
* MC0024, `credo_checks/no_markup_substring_assertion.ex` — the check
  that already blocks `=~` on `data-`/`phx-`/`class=`/`id=` literals;
  the sweep finds what predates it or routes around it through
  `has_element?`.
* [ADR-027](../decisions/architecture/2026-03-07-027-regression-tests-append-only.md)
  — the append-only files, out of scope.
* [ADR-049](../decisions/architecture/2026-05-22-049-testing-principles.md)
  — the testing principles the kept tests are measured against.
* `.claude/skills/automated-testing/SKILL.md` — the red-first rule whose
  residue this campaign clears.
* `serial-test-audit.md` — the sibling campaign on the same suite,
  on a different axis (wall time, not value).
* The picker-centring commit on 2026-10-28 (`fix(profiles): the
  in-shell picker centres …`) — the case that opened this.
