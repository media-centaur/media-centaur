---
status: accepted
date: 2026-09-17
---
# No Elixir dead-code gate; JS keeps one

## Context and Problem Statement

Nothing in the toolchain could see that a `def` has no callers.
`--warnings-as-errors` finds unused private functions, vars, aliases and
imports; `deps.unlock --unused` finds unused dependencies; the `:boundary`
compiler finds illegal cross-context edges. A **public** function whose last
caller was deleted was invisible, in Elixir and in JS alike. The v1.32.0
console rework left four such functions behind in one campaign, two found
only because a human happened to grep.

`mix_unused` was adopted to close the Elixir half, with the stated goal of
gating it in `mix precommit`. It ran for one campaign — sixteen commits — and
this record is the result of that evaluation.

`mix xref` is not an alternative: `mix xref callers` takes a module, never a
function. Nor is a custom Credo check: Credo is single-file AST analysis with
no cross-module call graph. This is the one house rule that cannot follow the
repo's usual "prefer a Credo check over prose" instinct.

## Decision Outcome

Chosen option: **remove `mix_unused`; keep the JS reachability gate.**

The tool's value was real but narrow, and it was not the value a gate
enforces.

**What it actually found.** Four defects, three of which had no symptom and
no other path to discovery:

* `Acquisition.CancelReasons` declared itself the source of truth for
  `cancelled_reason` while the database held four values it did not declare —
  no value in common. Its test asserted every constant was in `all/0`:
  perfect internal consistency about a set nothing held.
* The Status page showed Discovery's slot count for the two pipeline stages
  Import owns, and compared saturation against the same fixed number, so half
  the pipeline could never report saturated at all. Its test drove ten
  concurrent starts on a stage that maxes at five.
* `Plans.exclude_unit/1` had no caller, but `"excluded"` was honoured in six
  production read sites and shipped user copy said *"you excluded this
  earlier"* — a state no control could produce.
* Cancelling a download reached the client and left the Target row in
  `seeking`.

The common shape: **a function with no caller is often the only observable
trace of a seam that was half-moved.** A rewrite that left its predecessor
standing, a writer whose door was never built, a vocabulary that drifted from
its storage. Each half is internally consistent and its tests pass, so
nothing else sees it.

**Why not gate on it.** A gate enforces "no uncalled public function", which
is the clutter half — the other ~40 findings, whose removal returned close to
nothing while consuming most of the campaign's time. None of the four defects
above would have been caught by a gate, because in every case the function's
existence was correct and something *else* was wrong.

**And it could not gate anyway.** `mix_unused` cannot see through a default
argument: a function defined `def f(a, b \\ x)` appears in the docs chunk once,
at its maximum arity, carrying `defaults: n`, so callers using the shorter
arity produce edges that never match. Measured on this repo: **40 of 338
hints, 39 of them live code** — `CoreComponents.show/2`, `Prowlarr.search/3`,
every `Platform.Autostart` door, the whole `SearchSession` API. The data for
a fix is present (`MixUnused.Exports` already reads `doc_meta`) and the fix is
about five lines, but `MixUnused.Config`'s `checks:` is a hardcoded struct
default that `Config.build/2` never reads from `mix.exs`, so a corrected
analyzer cannot be injected. The reachable workaround — a 2-arity `ignore`
predicate on `doc_meta[:defaults]` — would silence 253 of this repo's public
functions to remove 39 false positives.

JS is different and keeps its gate: `no-unreachable-from-app` in
`.dependency-cruiser.cjs` walks reachability from the `app.js` entry point,
is precise, and already runs inside `mix boundaries` in `precommit`.
(`no-orphans` was measured and does nothing — an orphan needs no incoming
*and* no outgoing edges, and every module is imported by its own test, so it
would have reported zero the day `hooks/console.js` died.)

### Consequences

* Good, because the build gate enforces only things worth enforcing. A red
  `precommit` on live code, 39 times over, would have taught contributors to
  reach for the ignore list.
* Good, because the three findings that mattered are now fixed and recorded,
  and the behaviours the campaign declared along the way — `Library.Writable`,
  `Library.OwnerTyped`, `Broadway.Acknowledger` on the three pipeline
  producers — improve the code on their own terms and stay.
* Bad, because Elixir has no dead-code detection at all now. Rot will
  accumulate, and the next campaign that moves a seam will leave its
  predecessor standing with nothing to say so.
* Bad, because rediscovering the four defect shapes above needs a person
  reading for them. If dead-code detection is reattempted, read this record
  first: the yield is about one real defect per twenty-five candidates
  examined, the marginal yield declines as obvious asymmetries are worked, and
  the productive reading is "which rewrite left its predecessor standing",
  not "disposition every hint".

### Left open

`Acquisition.Targets.list_auto_targets/1` and `rearm_target/1` are a
capability with no door — shaped for a per-target admin table that does not
exist, since Downloads shows pursuits rather than target rows. Recorded at
the definition site in the `Targets` moduledoc, which is where someone will
meet it.
