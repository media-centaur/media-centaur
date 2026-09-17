---
status: planning
started: 2026-09-17
last_updated: 2026-09-17
---
# Dead-code detection

## Goal

Nothing in the toolchain can see that a `def` has no callers. Every other
category of rot is caught — `compile --warnings-as-errors` finds unused
private functions, vars, aliases and imports; `deps.unlock --unused` finds
unused dependencies; `boundaries` finds illegal cross-context edges — but a
public function whose last caller was deleted is invisible, in Elixir and in
JS alike.

That is not hypothetical. The v1.32.0 console rework produced **four** verified
instances in one campaign, two of them found only because a human happened to
grep (see Seed set). One of those, `Buffer.recent/1`, still had a production
caller in the incident-report path and would have crashed the error reporter at
runtime.

## Status

Planning. Nothing implemented. Two candidate tools identified, one cheap and
one needing a spike.

## Decisions made

* `2026-09-17` — Split from the console/log-rings work rather than bolted onto
  it. That campaign shipped as v1.32.0 (tag `v1.32.0`, commit `f4ef0d1b`); its
  dead-code leftovers seed this one.
* `2026-09-17` — `mix xref` is **not** a substitute. `mix xref callers` takes a
  *module*, not a function, so it answers "who uses `Console`" and never "who
  calls `journal_reconnect/0`".
* `2026-09-17` — A custom Credo check is **not** the right shape. Credo is
  single-file AST analysis; it cannot see a cross-module call graph. This is
  the one house rule that can't follow the repo's usual "prefer a Credo check
  over prose" instinct.

## Next steps

1. **Enable dependency-cruiser's `no-orphans` rule.** `.dependency-cruiser.cjs`
   currently carries exactly one rule (`core-no-app-imports`). The tool already
   runs via `mix boundaries`, so this is config, not a new dependency — the
   cheapest win available. It would have flagged `assets/js/hooks/console.js`
   the moment the drawer stopped registering it.
2. **Spike `mix_unused` against this toolchain.** `{:mix_unused, "~> 0.4.1"}` is
   purpose-built — a compiler tracer reporting public functions with no callers.
   **Last released 2023-06-29**, so it predates Elixir 1.20 / OTP 29 and hooks
   the compiler tracer API, which is exactly the part likely to have drifted.
   Verify it runs at all before planning around it.
3. **If the spike passes**, slot it into `precommit` beside `boundaries`, and
   decide the exemption mechanism — public API deliberately kept for callers
   outside the repo (mix tasks, `@doc` examples, `mc-eval` entry points) will
   need one, and it should be a declaration, not a global ignore list.
4. **If the spike fails**, record that here with the error, and fall back:
   dead public functions stay a review concern, with the mitigation that
   whoever deletes a caller greps for the callee. Do **not** substitute a
   Credo check — see Decisions.
5. **Clear the seed set** either way; it is small and each item is verified.

## Seed set — verified dead, 2026-09-17

Real instances to validate any tool against. Each was confirmed by grep at the
time of writing; re-confirm before deleting.

| Item | Evidence |
|---|---|
| `Console.journal_reconnect/0` | Only `JournalSource.reconnect(name)` in its own tests. The drawer's Reconnect button was the sole production caller and went with the drawer. Decide: re-add the affordance to the Status journal panel, or drop the function. |
| `mc:log-tail:repin` event | `assets/js/hooks/log_tail.js` adds/removes the listener; nothing anywhere dispatches it. |
| `data-pin-to="bottom"` mode | The attribute appears only in `log_tail.js`'s own comments. No markup sets it, so bottom-pin is unreachable. Removing it deletes a `describe` block of LogTail tests. |
| `solo_component` / `mute_component` handlers | `console_page_live.ex:173-180`. `chip_row` only ever emits `toggle_component`. Pre-dates the console rework. |

## Completion criteria

* A tool in `mix precommit` (or `mix boundaries`) fails on an unused public
  function, in Elixir or JS — **or** this file records why that is not
  achievable on this toolchain, with the spike's actual error.
* The seed set is empty: each item deleted, or kept with a one-line reason in
  its own moduledoc.
* If a tool lands, its exemption mechanism is documented where a contributor
  will meet it — the check's own message, not prose here.

## Pointers

* `.dependency-cruiser.cjs` — one rule today; `no-orphans` is the gap.
* `mix.exs` `precommit` alias — where an Elixir check would slot in.
* `docs/superpowers/specs/2026-09-16-subsystem-log-rings-design.md` — the
  campaign that produced the seed set.
* [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
  — campaign convention.
