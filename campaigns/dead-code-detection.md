---
status: in-progress
started: 2026-09-17
last_updated: 2026-09-17
---
# Dead-code detection

## Goal

Nothing in the toolchain could see that a `def` has no callers. Every other
category of rot was caught — `compile --warnings-as-errors` finds unused
private functions, vars, aliases and imports; `deps.unlock --unused` finds
unused dependencies; `boundaries` finds illegal cross-context edges — but a
public function whose last caller was deleted was invisible, in Elixir and in
JS alike.

Not hypothetical: the v1.32.0 console rework produced four such instances in
one campaign, two found only because a human happened to grep. One,
`Buffer.recent/1`, still had a production caller in the incident-report path
and would have crashed the error reporter at runtime.

## Status

Both detectors exist. **JS is gated**; Elixir is not yet.

| | state |
|---|---|
| JS | **Done.** `no-unreachable-from-app` at `error` in `.dependency-cruiser.cjs`, gating through `mix boundaries`, which is already in `precommit`. Tree clean. |
| Elixir | `mix_unused` configured and working, behind `MC_UNUSED=1`. **363 raw hints, 25 with no caller anywhere.** Not in `precommit` — gating before the list is empty means a red gate nobody can clear. |

Twelve commits, `f2d63496`..`615c7ac0`, unpushed. 19 functions deleted, two
features wired rather than deleted, two behaviours added, one architectural
defect fixed (`CancelReasons`).

# START HERE — how to work this

Read this section before dispositioning anything. Everything in it was learned
the hard way in this campaign; skipping it means repeating a mistake that has
already been made.

## The report

```bash
MC_UNUSED=1 ~/scripts/agents/agent-mix compile --force
```

`--force` is required: an incremental compile only traces what it recompiled.
Never bare `mix` — see the CLAUDE.md note on `agent-mix`.

The **"should be private"** lines (317 of them) are a *different* finding —
public functions used only inside their own module. They are an encapsulation
question, not dead code, and are out of scope until the dead-code list is
empty. `MixUnused.Config` does not let you disable that analyzer.

## Two blind spots — check BOTH before believing any hint

1. **Calls from a module body.** `Unused.analyze/2` builds its graph with
   `for {mfa, %{caller: {f, a}}} <- calls`; a module-body call carries
   `caller: nil`, the clause fails, and the edge is dropped **silently**. So
   `@attr Module.fun()`, `use` blocks and compile-time constants are invisible.
2. **Dynamic dispatch** — on a variable module (`schema.create_changeset(x)`),
   through `apply/3`, or from a `{module, function}` tuple in config (Phoenix
   `put_root_layout`, our own registries).

There is **no template blind spot.** That was believed briefly and written
into this file; it was wrong, asserted from one data point. `~H` and `.heex`
both trace correctly — 127 function components exist and only 19 were ever
flagged.

## The transitive cascade — why one seam hides many functions

The analyzer computes `Graph.reaching_neighbors/2`: a function is reported
when *every* transitive caller is itself unreached. One invisible root
therefore poisons its whole subtree. Most of the list is not independent
findings; it is a handful of seams and their fallout. **Fix the seam, not the
symptom** — one `Writable` declaration cleared 17 hints at once.

## The three mechanisms, in the order to reach for them

| | when | note |
|---|---|---|
| **A behaviour** | a real contract with several implementors | The only option that improves the code on its own terms: compiler-checks implementors, states intent where a contributor meets it, and the tool respects it natively. See `Library.Writable`, `Library.OwnerTyped`. |
| **`@doc export: true`** | a leaf entry point reached from outside the repo (`Release`, `Diagnostics`) | Definition-site declaration. **Does not propagate** — useless for anything that calls onward. |
| **`unused: [ignore: …]`** in `mix.exs` | a framework dispatcher you don't own, or your own runtime registry | Bluntest, and the **only one that breaks a cascade**. Every entry must name its seam in a comment. |

Do **not** make a runtime registry static to please the tool. The Status
widget registry dispatches through config precisely so the board takes no
compile-time dependency on every subsystem; collapsing it would reintroduce
the coupling it exists to remove.

## The rule that matters most

**Check the read side, not just callers, before recommending a delete.**

Three times a "clearly dead" item was not dead, and the last one was ruled
delete on a recommendation that had checked callers only:

* `CancelReasons` — an architecture defect, not rot (below).
* `Person.*_changeset` — a cascade artifact.
* `Plans.exclude_unit/1` — the writer had no caller, but `"excluded"` was
  honoured in **six** production read sites and shipped user copy *"you
  excluded this earlier"*. Deleting the writer would have left six readers and
  two strings pointing at an unreachable state. It was a feature missing its
  control; the control was built instead.

Of ~51 candidates examined, **19 were deletable**. Assume a hint is wrong
until the read side says otherwise.

# What is left

## The 25 with no caller anywhere

**Seven are known-alive cascade artifacts — do not delete.** Verified callers:

| function | real caller |
|---|---|
| `HttpClient.Cache.Coordinator.entry_count/1` | `Cache.stats/1` |
| `Library.FilePresence.list_relink_candidates/1` | `Relink` |
| `ReleaseTracking.Wants.dismiss_for_release/1` | `ReleaseTracking` |
| `TMDB.Client.search_multi/2` | `TMDB.TitleSearch` |
| `ReleaseTracking.find_last_library_episode/1` | its own `defdelegate` + `LibraryLinks` |
| `Watcher.Walk.real_fs/0` | a default argument in `walk/3` |
| `Library.PlayableItems.leaf_types/0` | rehomed — see `playable-item-versions.md` |

**The remaining ~18, grouped by the question each poses:**

* **A feature missing its control.** `Acquisition.plan_tracked_item_now/1` —
  a `defdelegate` to `DropPlanner.plan_item_now/2`, documented as *"the bulk
  gesture since ADR-056"*, with no UI control and no caller but its own test.
  Same shape as `exclude_unit` was. **No campaign owns it**; it needs a home
  before this file can be deleted.
* **Event predicates (3).** `event?/1` on `PlanEvents`, `TargetEvents`,
  `Pursuits.Events` — identical shape in three places, no caller in any. Looks
  like a dispatcher that never landed. Check for a seam before deleting.
* **Superseded pursuit doors (2).** `Pursuits.status_for/1`, `targets_for/1` —
  `incoming_live.ex:2005` carries a comment about *"the previous
  `Pursuits.status_for/1` path"*, so these read as superseded, not unfinished.
* **Two function components.** `Detail.Section.section/1`,
  `Detail.TitleLayer.title_layer/1` — both have stories (MC0009). Check
  whether anything mounts them.
* **The rest, one at a time.** `CourSegmentation.default_gap_days/0`,
  `TitleDownloadParams.{for_ref/2, get_many/1}`, `Activities.get_many/1`,
  `Format.iso_date/1`, `Pipeline.Import.processor_concurrency/0`,
  `Playback.Sessions.playing?/1`, `SelfUpdate.Changelog.recent/1`,
  `WatchHistory.Stats.total_seconds/1`, `GuideMarkdown.prose/1`.

## Deferred with a reason

* **Context facade erosion.** `Acquisition` fronts `Targets` with five
  `defdelegate`s because `Targets` is not a Boundary export — the facade is
  the only door another context has. Three of the five have no caller
  (`list_auto_targets/1`, `rearm_target/1`, `cancel_target/2`). Same question
  the `Containers` pass answered; decide it the same way.
* **`Containers.update/2`** kept deliberately: deleting it strands the three
  `update_changeset/2` implementations it solely calls, and it sits on an
  unanswered product question — a series' `status` is set once at import and
  nothing refreshes it, so a show that ends stays `:returning` forever.
* **Usenet half of the cancel fix.** `cancel_download/1` closes a torrent's
  target by infohash; a usenet job id is not stored on any target, so those
  still fall to the watcher. The complete fix is a `Pursuits.Policy` rule for
  "the download left the queue", which needs an observation window so a single
  missing snapshot cannot cancel a live download.

## Then gate

Once the list is empty: move `:unused` out from behind `MC_UNUSED=1`, set
`severity: :warning` + `--warnings-as-errors`, add it to `precommit` beside
`boundaries`.

# Decisions made

* `2026-09-17` — Split from the console/log-rings work (shipped v1.32.0, tag
  `v1.32.0`, commit `f4ef0d1b`); its dead-code leftovers seeded this one.
* `2026-09-17` — **`mix xref` is not a substitute.** `mix xref callers` takes a
  *module*, never a function.
* `2026-09-17` — **A custom Credo check cannot do this.** Credo is single-file
  AST analysis with no cross-module call graph. The one house rule that can't
  follow the repo's usual "prefer a Credo check over prose" instinct.
* `2026-09-17` — **`mix_unused` adopted** (`~> 0.4`, `only: [:dev]`). Despite
  its 2023 release the tracer API has not drifted; it runs on Elixir 1.20.4 /
  OTP 29 and found `Console.journal_reconnect/0` unprompted.
* `2026-09-17` — **The tracer runs in `:dev`, deliberately.** `:dev`
  `elixirc_paths` is `["lib", "credo_checks"]`, so a caller living only in
  `test/` is invisible and its callee is reported. That is a feature: "the
  only thing calling this is its own test" is itself a finding.
* `2026-09-17` — **`no-orphans` is the wrong JS rule.** Measured before being
  trusted: it reports zero across `assets/js/`, because an orphan needs no
  incoming *and* no outgoing edges and every module is imported by its own
  test. It would have reported zero the day `hooks/console.js` died. A
  `reachable` rule from the `app.js` entry point is what works. `mix
  boundaries` was also widened from `assets/js/input/` to `assets/js/` — as
  scoped it could never have seen `hooks/`.
* `2026-09-17` — **Prefer a behaviour over an ignore entry for a dispatch
  seam** (see the mechanism table above).
* `2026-09-17` — **Candidate counts are a floor.** Group counts were built
  from a name-only grep of `test/`, which hides any candidate whose function
  name appears anywhere in the suite. The vocabulary group was listed as 8 and
  was 16; the changeset group as 12 and was 22. Re-derive per group from the
  raw report.

# What was done

Four groups worked. Detail is in the commits; the lessons are in START HERE.

| group | outcome |
|---|---|
| **Seed set** (4) | `94997d03`. Journal **Reconnect** button restored (kept by restoring its caller); `mc:log-tail:repin` and `data-pin-to="bottom"` deleted from `LogTail`; solo/mute console stack deleted. Plus `Router.api/2` — phx.new scaffolding whose `pipe_through :api` lived only in a comment. |
| **Vocabulary** (16, not the 8 listed) | `b224eb3d`, `2251dcf2`. 2 struck as module-attribute artifacts, 3 rehomed to `playable-item-versions.md`, 5 schema enum getters deleted, and `CancelReasons` rewritten — see below. |
| **Changesets** (22, not 12) | `2251dcf2`, `f9e1275b`. **20 of 22 were not dead.** One `Library.Writable` behaviour cleared 17; `Image.update_changeset/2` was the one genuinely dead function hiding among eleven live look-alikes. ImageQueue's per-entry API deleted — production used only the batch forms. |
| **Containers** (7) | `5ee09e24`. Half the module's public surface had no production caller — an over-complete CRUD shape left by the refactor that collapsed four per-type modules into one. Four deleted, three kept with reasons at the definition site. Surfaced a second dispatch seam → `Library.OwnerTyped`. |

## The `CancelReasons` case — the campaign's exemplar

Worth reading before dispositioning anything that looks like a vocabulary.

It declared itself *"the single source of truth"* for `cancelled_reason` while
the Pursuits commands wrote their own literals. The declared set and the
stored set had **no value in common**: the live database held
`pursuit_satisfied`, `pursuit_cancelled`, `download_failed` and
`replaced_by_pick`, none of which it declared, and its moduledoc named
`acquisition_grabs` — a table renamed on 2026-05-11.

Its test had passed throughout, asserting every constant was in `all/0`:
perfect internal consistency about a set the database never held. **A test can
be green and guard nothing.** The new test names the write site for each
reason and failed red before the fix.

Deleting its seven uncalled accessors — the obvious reading — would have
cemented the drift.

## Wired, not deleted

Two candidates were missing controls, not rot. Both are now reachable, which
is what took them off the list (`8119820f`).

* **`exclude_unit`** — a plan-board cell is now a button: click drops that
  episode, click again restores it. Needed `PlanUnit.include_unit_changeset/1`
  (the inverse the schema never had) and `Plans.toggle_unit_excluded/1`, which
  reads direction from the **stored** unit so a stale board cannot exclude
  twice. No per-cell tooltip: UIDR-029 puts cell information on the grid's
  caption line because a gamepad user never sees a cursor tooltip — the first
  attempt added one and `incoming_live_test` rejected it.
* **`cancel_target`** — cancelling a download reached the client and left the
  Target row in `seeking`, because `Pursuits.Policy` decides on queue
  observations and has no rule for "the item is gone".
  `Acquisition.cancel_download/1` now closes it with
  `CancelReasons.user_request()`.

## Two traps that bit, both caught by the compiler

* **Deleting a function whose `@doc` is a separate attribute** leaves the doc
  attached to the *next* function, silently. Happened twice.
  `--warnings-as-errors` caught both; reading the diff would not have.
* **A function that starts touching the Repo needs its test moved to
  `DataCase`.** `cancel_download/1` gained a DB read and three routing tests
  failed with `DBConnection.OwnershipError` — only in the full suite, not in
  the targeted run.

## Inherited follow-ups

Carried from the console/log-rings campaign (shipped v1.32.0) so they live in
the repo rather than in one contributor's notes. **They are deliberately NOT in
this campaign's completion criteria** — they are unrelated scope and would turn
a sharp goal into a bucket.

**This file is deleted when the campaign completes (ADR-042). Anything still
open here must be rehomed first — its own campaign, an issue, or a moduledoc —
never dropped with the file.**

### Testing seams

* **The journal toggle's happy path has no CI coverage.** Nothing exercises
  "expand → subscribe → lines render → close → unsubscribe". The decision is
  pinned by `StatusLive.JournalPanel` (pure) and the lifecycle by
  `journal_source_test.exs` against a named instance, but the *join* between
  them was proven only by a manual browser probe (a `pgrep journalctl` poller
  showing the process appear on expand and die 5s after the drill-in closed).
  Closing it properly needs a named-instance seam on `JournalSource` reached
  through config. That is a **production** change and was deliberately not made
  for testability alone — it is a decision, not a test hack.

  **The surface grew on 2026-09-17.** The panel now carries a **Reconnect**
  button. Its handler has a regression test (it must tolerate a failing call —
  `journalctl` can die between the render and the click), but the happy path
  it belongs to is still the uncovered one: expand → subscribe → reconnect →
  lines resume. Verified manually in the browser against the dev instance,
  which runs under systemd and so is the only place the control renders at
  all.

* **`console_page_live_test.exs` seeds the ring with `Log.warning`.** That is
  captured by `ErrorReports.LogHandler`, mints an incident, and the `Buckets`
  server's async `{:buckets_changed, snapshot}` lands in a *later* test's Status
  LiveView, replacing its injected fixture. Real, pre-existing, seed-dependent
  flake source — it bit once during Phase C and was worked around there by
  seeding via `Console.Buffer.append/1` + `Console.flush()` instead. The test
  file still does it the old way.

### Scheduled convergences (from the log-rings spec)

Each has a named trigger; see
`docs/superpowers/specs/2026-09-16-subsystem-log-rings-design.md`.

* **`Retention` ↔ `HealthBoard` subsystem vocabulary.**
  `Retention.Policy.subsystem` is a **domain** field whose moduledoc constrains
  it to "one of the Status-page health-board subsystem keys" — a domain context
  constrained by a web module, enforced by prose alone. `ErrorReports` likewise
  folds via `HealthBoard.normalize/1` at display time. *Trigger: the next time a
  third context needs the subsystem vocabulary*, promote it to a domain module
  and make Retention's constraint a code reference.

* **Pending-review count is rendered in two widgets.** The Library widget shows
  "pending review + in-flight acquisitions"; the Metadata widget shows a
  pending-review low-confidence match count with a `~p"/review"` link. One idea,
  two representations, in adjacent tiles. *Trigger: consolidate these before
  anyone asks whether Review deserves its own Status tile* — it currently looks
  unnecessary precisely because its health is already on the board twice.

* **`:http` / "Connections" is a lens, not a subsystem.** Every other tile's
  description names a capability; this one names a layer. Its log panel shows
  requests made *on behalf of* TMDB, Downloads, Social and Updates, so one
  subsystem's failure can legitimately appear in two tiles' logs. Not wrong
  enough to remove — it has real health of its own. *Trigger: the next time the
  board's tile vocabulary is revisited*, decide explicitly whether cross-cutting
  lenses get their own row or a different visual treatment.

### Smaller

* **Owner-deferred docs:** `docs/GLOSSARY.md` and `.claude/skills/troubleshoot/SKILL.md`
  still describe the retired console drawer. `CLAUDE.md`, `docs/architecture.md`,
  `docs/playback.md` and the wiki were updated in v1.32.0.
* **`StatusLive.handle_params` re-reads 200 log lines from the Buffer on every
  patch** while a drill-in is open, including opening/closing an incident. A
  GenServer call on an operator page — acceptable, but noted.

# Completion criteria

* A tool in `mix precommit` (or `mix boundaries`) fails on an unused public
  function, in Elixir or JS.
  * **JS: met** (2026-09-17) — `no-unreachable-from-app` at `error`, verified
    to fail on a planted module.
  * **Elixir: pending** — gating waits on the candidate list reaching zero.
* ~~The seed set is empty~~ — done 2026-09-17.
* **Every candidate is dispositioned, not just cleared.** A hint leaves the
  list by one of three outcomes — invisible caller (declare or ignore),
  deliberate keep (with the reason at the definition site), or delete.
  Silencing the report without deciding is a failure of this campaign, not a
  completion of it.
* Every **Inherited follow-up** still open has been rehomed before this file
  is deleted. They do not gate the campaign, but they must not disappear with
  it. `Acquisition.plan_tracked_item_now/1` currently has no home.

# Pointers

* `mix.exs` — `unused/0` holds the ignore list (each entry names its seam);
  `unused_compiler/0` gates `:unused` behind `MC_UNUSED=1`.
* `.dependency-cruiser.cjs` — `core-no-app-imports` and
  `no-unreachable-from-app`; the latter is the JS dead-code gate.
* `lib/mix/tasks/boundaries.ex` — scans `assets/js/`, runs in `precommit`.
* `lib/media_centaur/library/writable.ex`, `owner_typed.ex` — the two
  behaviours that state a dispatch contract; copy their shape for the next one.
* `deps/mix_unused/lib/mix_unused/analyzers/unused.ex` — the transitive
  analyzer, and where both blind spots are visible in the source.
* `docs/superpowers/specs/2026-09-16-subsystem-log-rings-design.md` — the
  campaign that produced the seed set.
* [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
  — campaign convention.
