---
description: Judgment-level code quality analysis — vocabulary, duplication, readability, context boundaries, and test-policy compliance beyond what `mix precommit` already enforces.
argument-hint: "[path-or-module (optional)]"
---

# Engineering Audit

You are performing a meticulous code review of the Media Centaur backend (Elixir /
Phoenix / LiveView / Ecto on SQLite). Your goal is real, actionable findings — not
noise. Every finding cites the exact file and line and explains *why* it matters in
terms of the project's own rules.

**Scope:** If `$ARGUMENTS` is provided, focus on that path or module. Otherwise audit
the full `lib/` tree plus `test/`.

**What is already enforced — do not re-audit it.** `mix precommit` runs
`compile --warnings-as-errors`, `format` (with Quokka rewrites), `credo --strict`
with the 30-odd custom checks in `credo_checks/` (MC0001–MC0028: predicate naming,
no abbreviated names, PubSub facades and transport, log macros, `:sys` introspection,
raw badge/button classes, typed component attrs, storybook coverage, typed-event
chokepoints, destructive file queries, `on_exit` DB access, markup-substring
assertions, Repo setup in tests, owned async in web, platform branching, native
confirm dialogs, artwork width, and more), Boundary as a Mix compiler, dependency-
cruiser for `assets/js`, `deps.audit`, `sobelow`, and the Elixir + bun suites. Assume
it is green. A finding that a Credo check or Boundary would catch is not a finding;
if you believe a mechanical rule is missing, propose a new Credo check (the house
preference is code-as-spec over prose).

**Authorities to read first:** `CLAUDE.md`, `AGENTS.md`, `docs/architecture.md`,
`docs/GLOSSARY.md`, and the `coding-guidelines` and `automated-testing` skills. The
user's global engineering rules apply too: no backward-compatibility layers or
fallbacks, simplest implementation that fully meets today's requirement, no
speculative abstraction or configuration, single-responsibility modules (a moduledoc
that needs "and" is a split candidate), established libraries over hand-rolled code.

**Bounded contexts are whatever `ls lib/media_centaur/` shows** (currently ~30
directories, from `acquisition` to `watch_history`). Each has a `use Boundary,
deps: [...]` declaration that is the canonical inter-context dependency list
([ADR-029]). Do not work from a memorised list.

---

## Analysis Passes

Work through each pass sequentially, reading the actual source. Do not guess.

### Pass 1 — Vocabulary & naming

- **Glossary discipline:** terms with a project meaning are defined in
  `docs/GLOSSARY.md`; coined terms, metaphors-as-terms, and two names for one concept
  are findings. Words with several project meanings must be split into explicit names.
- **User/code vocabulary split:** code says `entity`, user copy says "entry";
  "release" is acquisition-only (see the `writing-copy` skill). Flag leaks in either
  direction.
- **Peer API shape:** peer contexts exposing equivalent operations under different
  names (`create_*` vs `insert_*`, `get_*` vs `fetch_*` outside the MC0022 lookup
  contract), inconsistent changeset builder names, inconsistent `{:ok, _} | {:error, _}`
  shapes for the same kind of operation.
- **Function names describe *what* in domain terms, not *how*.**

### Pass 2 — Duplication & missing abstractions

- Literal or near-literal blocks in several places.
- Structural duplication: modules that follow the same multi-step recipe
  independently (a behaviour, shared module, or component would unify them).
- Data duplication: one concept modelled by two structs, or derived in two places.
- Informal contracts (same function names and arities across modules) without a
  behaviour.

Suggest the abstraction only when it genuinely simplifies. Three similar lines beat a
premature abstraction; the house rule is "grow in layers", not "abstract early".

### Pass 3 — Readability & expressiveness

- Deeply nested `case`/`cond`/`with`, long functions doing unrelated things,
  nil-punning (`value && value.field`), catch-all `_ ->` clauses that swallow cases.
- Raw primitives or bare maps where a struct or tagged tuple would make impossible
  states unrepresentable.
- Comments: explain *why*, not *what*; stale comments that no longer match the code
  are findings (quote both).
- Stopgaps: anything commented or shaped as "for now", "temporary", "legacy",
  "compat", "fallback to the old …" — the project removes obsolete paths instead of
  keeping them.

### Pass 4 — Structure & boundaries

- **Single responsibility:** modules or contexts whose moduledoc needs "and"; contexts
  mixing read-model projection with write-side commands without a stated reason.
- **Boundary declarations as design, not just as a compiler gate:** deps lists that
  are broader than the code needs, contexts that reach sideways into a sibling's
  schemas rather than its public API, web modules that should go through a context
  facade ([ADR-029] data decoupling).
- **Cohesion and discoverability:** functions that belong in a different module
  given the directory-as-domain layout; public functions used only internally.
- **Processes without a runtime reason:** a GenServer, Agent, or Task where plain
  functions would do (no persisted state, no concurrency, no fault isolation).
- **Documentation placement:** module-internal contracts belong in `@moduledoc`;
  repository-wide decisions belong in `decisions/` (ADR/UIDR). Flag concepts
  documented in the wrong place or not at all.

### Pass 5 — Test-policy compliance

Audit against the `automated-testing` skill (read it), not against generic advice:

- **Test-first evidence:** new behaviour without a covering test; pure modules
  (parser, mappers, projections, console filter/view, playback resume, progress
  summaries) without a direct unit test.
- **What we never test:** rendered-markup substring assertions, GenServer internals,
  framework behaviour, static config text ("config-content grep tests"). Tests whose
  deletion would not fail if the feature were removed are tautological.
- **LiveView logic extraction:** business logic living in `handle_event` bodies and
  tested only through `render_click` instead of an extracted pure module.
- **Page smoke coverage:** every route and zone in `router.ex` has a smoke test.
- **Factories:** `MediaCentaur.TestFactory` (`build_*` pure, `create_*` DB); inline
  `Repo.insert!`/changeset boilerplate that duplicates it.
- **Reproducibility:** no network, no TMDB, no real show titles outside
  `test/media_centaur/parser_test.exs`; async ownership per [ADR-049]; global state
  goes through `GlobalStateSandbox`.
- **Append-only regression tests** ([ADR-027]): flag regression tests that were
  weakened or deleted (check `git log -p` for the file when in doubt).
- **Flake hygiene:** timing-based assertions (`Process.sleep`, `assert_receive` with
  generous timeouts as the primary sync) instead of the render-settle / owned-async
  patterns.

### Pass 6 — Beyond the linters

Things `mix precommit` cannot see:

- `String.to_atom/1` on untrusted input; `Repo.*` in loops that should be one query
  (an N+1 that Credo does not model).
- Dead code: functions and modules with no callers (verify with grep, not memory);
  unused Settings keys; feature flags with a single value.
- Migrations: a schema change without its paired safe migration, or a backfill that
  is not idempotent (safe-migration policy; MC0015 covers row mutation in schema
  migrations but not the policy as a whole).
- Observability gaps: a new subsystem with no `MediaCentaur.Log` component tag, or a
  failure path that neither logs nor raises a Status-page condition.

---

## Output Format

Number findings **E1, E2, …** and group them by pass. For each:

1. **Location** — `file_path:line`
2. **Issue** — one sentence
3. **Why it matters** — grounded in a named project rule, ADR, skill, or glossary
   entry
4. **Suggested fix** — concrete and minimal, or "judgment call, noting for awareness"

End with a **summary**: findings per pass, the top 3 highest-impact improvements, and
a one-paragraph health assessment.

Do not manufacture findings, and do not manufacture praise. If a pass is clean, one
sentence suffices. This command is analysis only: do not modify files. Output goes to
the chat; the user decides what to persist.
