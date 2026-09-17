---
status: in-progress
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

`mix_unused` spike **passed** — it runs clean on Elixir 1.20.4 / OTP 29, and the
`:unused` compiler plus its ignore config is wired into `mix.exs` behind
`MC_UNUSED=1` (gated so the always-on dev server's compiles stay quiet).
Configured, it cuts **1317 raw hints to 68 real candidates**. Not yet in
`precommit` — it would fail on those 68, which have to be dispositioned first.

**The JS half is done and gated.** `.dependency-cruiser.cjs` carries a
`no-unreachable-from-app` rule at `error`, and `mix boundaries` — already in
`precommit` — now scans `assets/js/` instead of just `assets/js/input/`. The
tree is clean today (87 modules, 0 violations) and a dead module fails the
build.

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

* `2026-09-17` — **`mix_unused` is adopted.** `{:mix_unused, "~> 0.4"}`,
  `only: [:dev]`. Despite the 2023 release date the compiler tracer API it
  hooks has not drifted: it compiles and reports correctly on Elixir 1.20.4 /
  OTP 29. It found `Console.journal_reconnect/0` — seed-set item 1 — on its
  own, with no prompting.

* `2026-09-17` — **The tracer runs in `:dev`, not `:test`, and that is the
  point.** `:dev` `elixirc_paths` is `["lib", "credo_checks"]`, so a caller
  that lives only in `test/` is invisible and its callee is reported unused.
  That is a *feature*: "the only thing calling this is its own test" is itself
  a finding. It also means the raw report cannot be read as a delete list —
  see Two-axis triage.

* `2026-09-17` — **Two exemption mechanisms, and they are not interchangeable.**
  The analyzer is transitive: `MixUnused.Analyzers.Unused` computes
  `Graph.reaching_neighbors/2` and reports a function whose every transitive
  caller is itself an uncalled public function. So one invisible root poisons
  its whole subtree.
  - `@doc export: true` — a **definition-site declaration**. Silences that one
    function only; its callees still cascade. Use for **leaf** entry points
    reached from outside the repo: `MediaCentaur.Release` (`bin/media_centaur
    eval`), `MediaCentaur.Diagnostics` (`mc-eval`).
  - `unused: [ignore: [...]]` in `mix.exs` — removes the MFA from the call
    graph, so it **also clears the subtree**. The only thing that works for a
    dynamic-dispatch **root** that composes other functions (the Status
    Activity widgets: `apply/3` off the `:health_activity_widgets` config
    registry, each composing the library-overview cards).

  This is the one place the campaign's "a declaration, not a global ignore
  list" preference cannot be fully honoured — the definition-site mechanism
  does not propagate. Every `ignore` entry names the seam in a comment.

* `2026-09-17` — **Calls from a module body are invisible to `mix_unused`.**
  `Unused.analyze/2` matches `%{caller: {f, a}}` when building its call graph;
  a call in a module body carries `caller: nil`, so the clause fails and the
  edge is dropped without warning. `@attr Module.fun()`, `use` blocks and
  compile-time constants therefore produce false positives. 8 of 424 hints.
  Check this before dispositioning anything.

* `2026-09-17` — **The candidate count is a floor, not a census.** The 66 came
  from a name-only grep of `test/`, which hides any candidate whose function
  name appears anywhere in the suite (`all/0`, `fetch/1`, `statuses/0`). The
  vocabulary group was listed as 8 and was actually 16. Re-derive per group
  from the raw report rather than trusting the grouped counts.

* `2026-09-17` — **`no-orphans` is the wrong rule; reachability is the right
  one.** The plan named `no-orphans`, and it was measured before being
  trusted: it reports **zero** violations across `assets/js/`, and would have
  reported zero the day `hooks/console.js` went dead. dependency-cruiser's
  orphan means *no incoming and no outgoing* edges — and every module here is
  imported by its own `.test.js`, so nothing is ever an orphan. The rule that
  actually works is a `reachable` rule from the `app.js` entry point with test
  paths excluded, landed as `no-unreachable-from-app` at `error`. Verified by
  planting a dead module and watching `mix boundaries` fail, then removing it.
  `mix boundaries` was also widened from `assets/js/input/` to `assets/js/`;
  scoped as it was, it could not have seen `hooks/` at all.

## Two-axis triage

A hint is not a delete order. Every candidate gets sorted on two axes before
anything is removed, because the tool answers only the first one:

1. **Can the compiler see a caller?** No → it reports the function.
2. **Should there be a caller?** The tool has no opinion. We do.

That gives three outcomes, and only one of them is a deletion:

| Outcome | Mechanism | When |
|---|---|---|
| **Invisible caller** | `ignore` (root) / `@doc export: true` (leaf) | A caller exists but goes through `apply/3`, a config registry, or `bin/media_centaur eval`. Nothing is wrong; the tracer just can't see it. |
| **Deliberate keep** | `@doc export: true` + a one-line `@doc` saying why | Genuinely uncalled today and we want it anyway — a domain vocabulary kept complete, an operator affordance reached from `mc-eval`. The reason goes next to the code, never in this file. |
| **Delete** | remove it, and its tests | Uncalled, and nothing about the design wants it called. |

The middle row is the one that needs care. "Nothing calls it" and "nothing
should call it" are different claims, and only the second justifies a deletion.

## Candidates — 66 at 2026-09-17, 414 raw hints after the vocabulary group

Full report: `MC_UNUSED=1 mix compile --force`. These are the hints with no
caller in `lib/` **and** no name match anywhere in `test/`, grouped by the
question each group poses.

> **The groups below are a reading aid, not a verdict — check every item
> individually.** Grouping them was tried and it misled: the "operator
> affordances" group was written on the guess that those functions were
> reached from `mc-eval`, and two of the six turned out to be neither
> operator affordances *nor* dead. `HttpClient.Cache.Coordinator.entry_count/1`
> is called by `Cache.stats/1`, and `Watcher.Walk.real_fs/0` is a default
> argument in `walk/3` — both are **cascade artifacts**, visible only because
> a caller further up is itself unreached. Cascade artifacts surface anywhere
> in the list, including inside groups that look obvious.

* ~~**Domain vocabulary kept complete.**~~ **Worked 2026-09-17 — see
  Vocabulary group below.** It was 16 items, not 8 (the group counts were
  built with a name-only `test/` filter that hid `all/0`, `valid?/1`,
  `statuses/0`, `fetch/1`, `create!/1`). It resolved into four different
  answers, only one of which was the vocabulary question as posed.

* ~~**Write paths nothing calls (12).**~~ **Worked 2026-09-17 — see Changeset
  group below.** It was 22, and 20 of them were not dead.

* **Event predicates (3).** `event?/1` on `PlanEvents`, `TargetEvents`,
  `Pursuits.Events`. Identical shape in three places, no caller in any.
  Looks like a dispatcher that never landed.

* **Features never wired (5).** `Plans.exclude_unit/1` +
  `PlanUnit.exclude_unit_changeset/1` (one affordance, two halves),
  `ReleaseTracking.Wants.dismiss_for_release/1`,
  `Acquisition.plan_tracked_item_now/1`, `Pursuits.status_for/1` +
  `targets_for/1`. *Question: was the UI dropped, or never built?*

* **The group that was checked (4 left of 6).** Written as "operator
  affordances"; checking it is what produced the warning above.
  `HttpClient.Cache.Coordinator.entry_count/1` (called by `Cache.stats/1`) and
  `Watcher.Walk.real_fs/0` (a default argument in `walk/3`) are cascade
  artifacts — struck. Still open, and none of them an `mc-eval` entry point:
  `Acquisition.test_prowlarr/0` + `test_download_client/1` (no caller
  anywhere; Settings reads `IntegrationHealth.verify/1` instead, so these look
  superseded), `ReleaseTracking.Refresher.refresh_all/0` (a public cast
  wrapper the interval timer bypasses — it calls `do_refresh_all/0` directly),
  `Profile.Reporter.runs_dir/0` (the module uses the `@runs_dir` attribute).

* **UI never mounted (6).** `Detail.Section.section/1`,
  `Detail.TitleLayer.title_layer/1`, `ReleaseTracking.Present.tone_dot_class/1`
  + `tone_text_class/1`, `IncomingLive.Logic.collapsible_head_size/0`,
  `LibraryAvailability.availability_for_dir/3`. Components with a story
  (MC0009) but no app caller — the exact gap the CLAUDE.md storybook note
  warns about.

* **Small utilities (8).** `Format.iso_date/1`,
  `WatchHistory.Stats.total_seconds/1`, `Playback.Sessions.playing?/1`,
  `SelfUpdate.Changelog.recent/1`, `TMDB.Client.search_multi/2`,
  `GuideMarkdown.prose/1`, `ArtworkWarmup.poster_urls/0`,
  `Acquisition.CourSegmentation.default_gap_days/0`.

* **Remaining (18).** `Activities.get_many/1`,
  `TitleDownloadParams.{get_many/1,for_ref/2}`,
  `Library.FilePresence.list_relink_candidates/1`,
  `Library.Person.put_credits/2`, `Pipeline.Import.processor_concurrency/0`,
  `Playback.SessionSupervisor.terminate_session/1`,
  `ReleaseTracking.find_last_library_episode/1`,
  `Social.Connections.subscribe_all/2` + `Connections.Owner.subscribe_all/2`,
  `Pursuits.Units.covering_target_ids/1`.

## Vocabulary group — worked 2026-09-17

16 items. One turned out to be an architecture defect, not dead code.

### Not dead — module-attribute blind spot (2, struck)

`TitleDetailHost.LibraryEvents.events/0` and `SetupLive.Probes.step_order/0`
are both called, from a module attribute:
`@library_events LibraryEvents.events()`, `@step_order [:welcome] ++
Probes.step_order() ++ [:summary]`.

**Generalizable:** `MixUnused.Analyzers.Unused` builds its graph with
`for {mfa, %{caller: {f, a}}} <- calls` — the pattern only matches when the
caller is a `{function, arity}` tuple. In a module body `env.function` is
`nil`, the clause fails, and the edge is **silently dropped**. So every call
made from a module body — a module attribute, a `use` block, a compile-time
constant — is invisible to the tool. Measured: **8 of 424** flagged hints are
this class (`Autostart.state/1`, `Connections.feed_sub_id/0`,
`RunData.schema_version/0`, `Translation.max_text_length/0`,
`Updater.status/1`, `Version.build_info/1`, plus the two above).

### Belongs to another campaign (3, rehomed)

`Library.PlayableItems.{leaf_types/0, create!/1, fetch/1}` — unused public API
of the half-landed "Library Schema v2 Phase 2" (`create/1` *is* used). Not
dead code; an unfinished migration. Owned by
[`playable-item-versions.md`](playable-item-versions.md).

### The real vocabulary question (5, deleted)

`ErrorReports.Incident.{origins/0, statuses/0, severities/0}`,
`ErrorReports.DiagnosticEvent.levels/0`,
`Acquisition.Plans.Plan.approval_policies/0`.

Identical shape in all five: a module attribute (`@origins`,
`@approval_policies`) *is* the source of truth and *is* used — by
`Ecto.Enum, values: @origins` and `validate_inclusion(…, @approval_policies)`.
The public getter only re-exposes it, and nothing reads it.

**Owner ruling 2026-09-17: delete.** A schema's enum set stays private until
something needs it; re-exposing it is one line the day a filter or admin view
does. All five removed, no validation changed. (The `Plan` cut left an
orphaned `@doc` that reattached to `create_changeset` — caught by
`--warnings-as-errors`, not by review.)

### `CancelReasons` — not a vocabulary question, a defect (9)

`MediaCentaur.Acquisition.CancelReasons` says of itself: *"Inline string
literals at call sites drift … This module is the single source of truth."*
It lost, and the evidence is unambiguous:

* Its moduledoc names `acquisition_grabs.cancelled_reason`. That table was
  **renamed to `acquisition_targets` on 2026-05-11** (migration
  `20260511190000_pursuit_target_recipe_refactor`).
* It declares 10 reasons. **3** have a caller (`user_request` in
  `incoming_live`, `item_removed` in `reactor`, `auto_grab_disabled` in
  `mode_reconciler`).
* The live dev database holds 4 distinct non-null values:
  `pursuit_satisfied` (109), `pursuit_cancelled` (25), `download_failed` (4),
  `replaced_by_pick` (1). **Zero overlap with the declared set** — not one
  declared reason appears in the data.
* The actual writers bypass it: the Pursuits commands use inline literals
  (`satisfy.ex:75`, `cancel.ex:39`, `pick_target.ex:64`) and
  `auto_cancel.ex:135` writes `Atom.to_string(policy_reason)` from
  `Pursuits.Policy`'s own atom vocabulary. `target.ex:221` defaults to the
  literal `"abandoned"`; `showcase.ex:845` writes `"user_cancelled"`. Neither
  is declared anywhere.

So one column has three vocabularies, and the declared one is the dead one.
**Deleting the 7 unused accessors would cement the drift** — which is exactly
why the campaign's rule is disposition, not deletion.

Worth separating before deciding: the live values may be two concepts sharing
a column — *why a target closed* in normal lifecycle (`pursuit_satisfied`,
`replaced_by_pick`) versus *why an acquisition was cancelled*
(`user_request`, `item_removed`). A flat set may be the wrong target shape.

**Owner ruling 2026-09-17: shrink to truth and adopt the writers.** Done.

* The declared set is now the 11 strings live code can actually write, each
  row of the moduledoc table naming its write site.
* Dropped 6 that nothing can write: `user_disabled`, `in_library`,
  `identity_mismatch`, `abandoned`, `stall`, `superseded_by_plans`. The last
  two are documented as historical values old rows may still carry.
* Converted 8 write sites from literals to accessors (`Commands.Satisfy`,
  `Cancel`, `PickTarget`, `ChangeTarget`, `Jobs.PursueTarget` ×2,
  `Showcase`), and `Commands.AutoCancel` now calls a new `from_policy/1`
  instead of `Atom.to_string/1` — so a new `Policy` decision can no longer
  mint a reason outside the set.
* `TimelineEntry`'s display mapping binds to the module too, closing the read
  side.
* Removed `Target.failed_changeset/2`'s `\\ "abandoned"` default: all four
  callers pass explicitly, so the default was itself unreachable — and it was
  the only thing that could have written `abandoned`.

**The test was the real lesson.** `cancel_reasons_test.exs` already existed
and passed throughout: it asserted every constant was in `all/0` and that
`valid?/1` accepted exactly those strings. Perfect internal consistency about
a set the database never held. The new block — "every reason production code
writes is in the set", naming each write site — is what the guard had to be,
and it failed red before the fix.

**Still reported, both explained:** `download_failed/0` and `zero_seeders/0`
(reached from `TimelineEntry` module attributes — the blind spot above), and
`all/0` + `valid?/1` (reached only from the test that guards the vocabulary,
kept deliberately with the reason at the definition site).

## Changeset group — worked 2026-09-17

22 items, not the 12 listed. **Two were dead.** The rest were one seam and its
cascade — the inverse of what the group name claimed.

### One behaviour cleared 17 (the fix)

`create_changeset/1`, `update_changeset/2` and `update_credits_changeset/2` are
dispatched on a **variable module** in five places — `Containers.create/2`,
`Writes.find_or_insert_by/3`, `Writes.upsert_by/3`, `Files.upsert_by_path/2`,
and `Maintenance`'s credits refresh. A call-graph tracer cannot see any of them,
so every Library schema's changesets looked dead.

The repo had already solved this once: `Library.ProgressTracker` is a
behaviour declaring exactly `create_changeset/1` + `update_changeset/2`, which
is why `WatchProgress` and `ExtraProgress` never appeared in the report. The
pattern was simply never extended.

**Owner ruling: declare the behaviour.** `MediaCentaur.Library.Writable` —
`create_changeset/1` required, `update_changeset/2` and
`update_credits_changeset/2` optional — declared on `TVSeries`, `MovieSeries`,
`Movie`, `VideoObject`, `WatchedFile`, `ExtraFile`, `Season`, `Episode`,
`Extra`. Raw hints **414 → 396**; every Library changeset hint cleared, and
`Person.{cast_member,crew_member}_changeset` (reached by function capture from
those changesets) cleared with them as cascade.

`containers_test.exs` now asserts every schema `Containers.schema/1` returns
declares the contract — derived from `Containers.types/0`, not a copied list,
so a new container type that forgets it fails. Verified by removing the
declaration from `VideoObject` and watching it fail.

This is why `ignore` was the wrong tool here: the behaviour is checked by the
compiler, states the contract where a contributor meets it, and cost nine
one-line declarations.

### Genuinely dead (2, deleted)

* `Library.Image.update_changeset/2` — no caller anywhere, and no seam passes
  `Image`. It sat among eleven live look-alikes; nothing but a call-graph tool
  was ever going to find it.
* `Router.api/2` — already removed earlier in the campaign.

### Still open — public API whose only caller is a test

Not dead, not obviously wanted. Each is a real capability the product does not
expose:

| cluster | shape |
|---|---|
| `ImageQueue.{update_status/2, mark_failed/1, reset_to_pending/1}` + `ImageQueueEntry.{status,fail,reset}_changeset` | Production uses **only** the batch variants, which bypass changesets via `Repo.update_all`. The tests exercise a path production never takes. |
| `Containers.update/2` — and six more `Containers` functions (`types/0`, `list/1`, `list_tv_series/2`, `get_with_associations!/2`, `destroy/1`, `find_child_movie_by_path/2`) | A context module that is mostly unreached. Bigger than one function; deserves its own pass. |
| `Acquisition.cancel_target/2` → `Targets.cancel_target/2` → `Target.cancelled_changeset/2` | A parallel door nobody opens: the UI's cancel calls `Acquisition.cancel_download/1`, which cancels at the **download client** and never touches the Target row. |
| `Plans.exclude_unit/1` + `PlanUnit.exclude_unit_changeset/1` | Zero callers, not even a test. **Not dead — see below.** |

### Owner rulings 2026-09-17

**ImageQueue: delete, migrate the tests. Done.** `update_status/2`,
`mark_failed/1`, `reset_to_pending/1` and `ImageQueueEntry.{status,fail,reset}_changeset`
removed — six functions production never called. The ~14 test call sites moved
onto the batch API the pipeline actually uses.

*ADR-027 note:* these are pipeline tests, which are append-only — "never
removed". Deleting a feature is not the weakening that ADR guards against, but
it has no carve-out, so each guard was **migrated** rather than dropped: the
successive-failure retry_count increment and the reset-without-clearing-retries
case now run against `mark_failed_batch/1` and `reset_to_pending_all/1` (the
latter had no coverage at all before). No failure mode lost its guard.

**`Containers`: its own pass, next session.** Seven flagged functions
(`update/2`, `types/0`, `list/1`, `list_tv_series/2`,
`get_with_associations!/2`, `destroy/1`, `find_child_movie_by_path/2`) is most
of a context module unreached from production. It asks what `Containers` is
still for — a bigger question than this group. **Not touched.**

**`exclude_unit`: ruled delete, then reversed on evidence. Not deleted.**
The ruling was given on my recommendation, and the recommendation was wrong —
I had checked callers but not the *read* side. `"excluded"` is honoured in six
production places: the planner rejects excluded units (`run_plan.ex:87`),
`Plans.units_for` filters them (`plans.ex:401`), `Claims` excludes them from
its query (`claims.ex:51`), `Board` both counts them out of "wanted"
(`board.ex:68`) and renders them (`cell_state/2` → `:excluded`), and
`Alternatives` skips them (`alternatives.ex:241`). The web layer ships the
copy: `cell_treatment(:excluded)` is *"muted strikethrough. User removed it
from the plan."* and `PlanLogic.reason_label(:excluded)` is *"you excluded this
earlier."*

So this is a feature built end-to-end except its control, with user-facing
copy for a state no code path can produce. Deleting the one writer would leave
six readers and two strings for an unreachable state — strictly worse than
today. **Disposition: wire the control, or remove the feature whole. Not a
dead-code decision.** Rehome to whichever campaign owns the plan board.

**`cancel_target`: investigated, unresolved.** `Acquisition.cancel_target/2` →
`Targets.cancel_target/2` → `Target.cancelled_changeset/2` marks the row
cancelled and broadcasts `TargetEvents.Cancelled`. It has no production caller:
the UI's cancel calls `Acquisition.cancel_download/1`, which cancels at the
**download client** and never touches the Target row. `Pursuits.Policy` has no
rule for "the download left the queue" — its auto-cancel rules are
client-reported terminal failure and zero-seeders.

Whether a user-cancelled download therefore strands its target in `seeking`
could not be settled from data: the live table holds 138 `cancelled`,
78 `succeeded`, 1 `failed` and **zero `seeking`**, so nothing is mid-flight to
observe. The test is inconclusive, not negative. Settling it needs a live
acquisition and a cancel — a runtime check, not a reading.

## Wired, not deleted — 2026-09-17

Two candidates turned out to be missing controls rather than dead code. Both
are now reachable, which is what took them off the list.

### `exclude_unit` — the plan board's per-unit control

The read side was complete and the writer had no caller. Rather than delete
the writer, the control was built:

* `PlanUnit.include_unit_changeset/1` — the inverse `exclude_unit_changeset/1`
  never had. Back to `pending`, not to the prior assignment: the exclusion
  cleared it, and today's releases are not the ones that were on offer then.
* `Plans.include_unit/1` and `Plans.toggle_unit_excluded/1`. The toggle reads
  direction from the **stored** unit, never from what the page last rendered,
  so a stale board cannot exclude the same unit twice.
* `plan_modal`'s `board_cell/1` is now a `<button>` carrying
  `phx-click="plan_toggle_unit_excluded"`, with `aria-pressed`. The
  strikethrough treatment that already existed is what it produces.
* **No `title` tooltip.** The first attempt added one and
  `incoming_live_test` rejected it: UIDR-029 puts cell information on the
  grid's caption line because *"a cursor never sees"* a tooltip on a surface
  navigated by gamepad. The excluded state got a `cell_title/1` clause
  instead, reusing `PlanLogic.reason_label(:excluded)`'s wording.

Verified in the browser: all 82 storybook cells render as buttons with the
handler, and the excluded one carries `line-through` + `aria-pressed="true"`.

### `cancel_target` — the gap was real

Cancelling a download from the UI cancelled it at the **client** and left the
Target row in `seeking`. `Pursuits.Policy` decides on queue *observations* and
has no rule for "the item is gone", so nothing closed the row until its attempt
budget ran out. `Acquisition.cancel_download/1` now closes it on the same act,
through `Targets.cancel_for_download/2` → `cancel_target/2` with
`CancelReasons.user_request()`.

Torrent ids are the infohash the target already stores. A usenet id is the
client's own job id, which no target carries, so those fall through untouched —
the watcher stays their only closer. **That half is still open**, and the
architecturally complete fix is a `Policy` rule for "the download left the
queue", which needs an observation window to avoid cancelling on a single
missing snapshot.

### Context facade erosion — grouped with the `Containers` pass

`Acquisition` fronts `Targets` with five `defdelegate`s because `Targets` is
not a Boundary export — the facade is the only door another context has.
Three of the five have no caller at all (`list_auto_targets/1`,
`rearm_target/1`, `cancel_target/2`); two do. That is the same question the
`Containers` pass asks, so it is deferred to it rather than decided piecemeal.

## Sweep state — 2026-09-17, end of the autonomous run

**366 raw hints; 26 with no caller anywhere.** Thirteen functions deleted in
the final batch (see `a19d6ea9`), each verified individually against callers,
dispatch seams, HEEx templates, storybook and tests.

### Already known to be alive — cascade artifacts, do not delete (7)

Verified callers; they appear only because something above them is unreached.

| function | real caller |
|---|---|
| `HttpClient.Cache.Coordinator.entry_count/1` | `Cache.stats/1` |
| `Library.FilePresence.list_relink_candidates/1` | `Relink` |
| `ReleaseTracking.Wants.dismiss_for_release/1` | `ReleaseTracking` |
| `TMDB.Client.search_multi/2` | `TMDB.TitleSearch` |
| `MediaCentaurWeb.ArtworkWarmup.poster_urls/0` | `root.html.heex`, via `Layouts.root/1` |
| `ReleaseTracking.find_last_library_episode/1` | its own `defdelegate` + `LibraryLinks` |
| `Watcher.Walk.real_fs/0` | a default argument in `walk/3` |

**Correction, same day.** `poster_urls/0` was first written up here as proof
of a third blind spot — "templates are not compiled through the tracer". That
was wrong, and asserted from one data point. Templates trace fine: 127 function
components exist and only 19 were ever flagged. The repo has exactly one
`.heex` file, and the actual cause is the ordinary one — `put_root_layout,
html: {Layouts, :root}` is a runtime config tuple, so `Layouts.root/1` is
itself flagged and everything its template calls cascades from it.

The fix was an `ignore` entry naming the layout seam, which cleared both.
There is no template blind spot; there are two, module bodies and dynamic
dispatch, and Phoenix's layout resolution is an instance of the second.

### Still to disposition (~19)

* **Features never wired.** `Acquisition.plan_tracked_item_now/1` — a
  `defdelegate` to `DropPlanner.plan_item_now/2`, documented as *"the bulk
  gesture since ADR-056"*, with no UI control and no caller but its own test.
  Same shape as `exclude_unit` was. **No campaign obviously owns it**; it
  needs a home before this file is deleted.
* **Event predicates.** `event?/1` on `PlanEvents`, `TargetEvents`,
  `Pursuits.Events` — identical shape in three places, no caller in any.
* **Pursuit view-model doors.** `Pursuits.status_for/1`, `targets_for/1` —
  `incoming_live.ex:2005` carries a comment about "the previous
  `Pursuits.status_for/1` path", so these look superseded rather than
  unfinished.
* **The rest**: `CourSegmentation.default_gap_days/0`,
  `TitleDownloadParams.{for_ref/2,get_many/1}`, `Activities.get_many/1`,
  `Format.iso_date/1`, `Library.PlayableItems.leaf_types/0` (rehomed —
  see `playable-item-versions.md`), `Pipeline.Import.processor_concurrency/0`,
  `Playback.Sessions.playing?/1`, `SelfUpdate.Changelog.recent/1`,
  `WatchHistory.Stats.total_seconds/1`, `GuideMarkdown.prose/1`,
  `Detail.Section.section/1`, `Detail.TitleLayer.title_layer/1`.

The last two are function components; check the HEEx blind spot above before
treating either as dead.

## Next steps

1. **Disposition the 68** against the three outcomes above. Cheapest order:
   operator affordances → `export: true`; `Router.api/2` → delete; then the
   groups that need a product call.
2. **Then gate.** Once the list is empty, move `:unused` out from behind
   `MC_UNUSED=1`, set `severity: :warning` + `--warnings-as-errors`, and add
   it to `precommit` beside `boundaries`. Gating before the list is empty just
   means a red precommit nobody can clear.
3. ~~**Enable dependency-cruiser's `no-orphans` rule.**~~ Done 2026-09-17,
   but **not with `no-orphans`** — see Decisions.
4. ~~**Clear the seed set.**~~ Done 2026-09-17 — see Seed set below.

## Seed set — cleared 2026-09-17

All four dispositioned. Kept here as the worked example of the three outcomes.

| Item | Outcome |
|---|---|
| `Console.journal_reconnect/0` | **Kept — caller restored.** The Status → System journal panel now carries a Reconnect button (`health_components.ex`, `StatusLive.handle_event("journal_reconnect", …)`). `journalctl` can die under an open panel — the unit restarts, the pipe breaks — and nothing else respawned it while a reader watched. The handler tolerates a failing call (no unit, no subscribers); regression test in `status_live_test.exs`. The stale `@doc` naming the retired drawer was corrected. |
| `mc:log-tail:repin` event | **Deleted.** Its own comment claimed it was "kept as the documented way to ask a tail to re-pin" — a deliberate keep, re-examined and overturned. `LogTail` is mounted on exactly one container (`#console-entries` on `/console`), which is never hidden-then-revealed, so the case the seam described does not exist here. The journal panel, the one surface that *is* revealed on expand, does not use the hook. |
| `data-pin-to="bottom"` mode | **Deleted.** Unreachable — no markup ever set it. The rail reads newest-first by design, so bottom-pin was a mode the design had already ruled out. `LogTail` is now top-pin only; the `updated()` re-pin tests were rewritten against top mode rather than dropped. |
| `solo_component` / `mute_component` | **Deleted, whole stack.** `console_page_live.ex` handlers, `ConsolePageLive.Logic`, `Console.Filter`, and their tests — the chips only ever emitted `toggle_component`. |

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

## Completion criteria

* A tool in `mix precommit` (or `mix boundaries`) fails on an unused public
  function, in Elixir or JS — **or** this file records why that is not
  achievable on this toolchain, with the spike's actual error.
  * **JS: met** (2026-09-17). `no-unreachable-from-app` at `error`, in
    `precommit` via `mix boundaries`, verified to fail on a planted module.
  * **Elixir: pending.** `mix_unused` works and is configured, but gating
    waits on the candidate list reaching zero.
* The seed set is empty: each item deleted, or kept with a one-line reason in
  its own moduledoc.
* **Every candidate is dispositioned, not just cleared.** A hint leaves the
  list by one of the three outcomes in Two-axis triage — and a "keep" carries
  its reason at the definition site. Silencing the report without deciding
  is a failure of this campaign, not a completion of it.
* If a tool lands, its exemption mechanism is documented where a contributor
  will meet it — the check's own message, not prose here.
* Every **Inherited follow-up** still open has been rehomed (its own campaign,
  an issue, or a moduledoc) before this file is deleted. They do not gate the
  campaign, but they must not disappear with it.

## Pointers

* `.dependency-cruiser.cjs` — `core-no-app-imports` and
  `no-unreachable-from-app`; the latter is the JS dead-code gate.
* `lib/mix/tasks/boundaries.ex` — scans `assets/js/`, runs in `precommit`.
* `mix.exs` — `unused/0` holds the ignore list (each entry names its seam);
  `unused_compiler/0` gates `:unused` behind `MC_UNUSED=1`; the `precommit`
  alias is where it slots in once the candidate list is empty.
* `MC_UNUSED=1 mix compile --force` — the report. Incremental `mix compile`
  only traces what it recompiled, so `--force` is required for a true count.
* `docs/superpowers/specs/2026-09-16-subsystem-log-rings-design.md` — the
  campaign that produced the seed set.
* [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
  — campaign convention.
