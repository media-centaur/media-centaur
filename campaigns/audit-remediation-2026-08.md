---
status: complete
started: 2026-08-05
last_updated: 2026-08-06
---
# Audit remediation — August 2026

## Goal

Work off the structural debt surfaced by the four-audit sweep of
2026-08-05 (engineering, performance, documentation, design). The
critical items already shipped; what remains is debt with real
consequences that no single feature ticket would ever justify fixing.
Each stage below is scoped to be discussable in one sitting and
resolvable in the next.

## Working agreement

**Discuss a stage before resolving it.** Each stage carries an *Open
questions* block — those are for the owner, not for the agent to
decide unilaterally. The loop per stage is:

1. Read the stage. Verify its facts still hold (`git log` + the
   evidence commands given) — the reconciliation rule applies here as
   much as to the campaign as a whole.
2. Bring the open questions to the owner and agree an approach.
3. Implement, test-first, `mix precommit` green.
4. Update this file — move the stage to **Done**, append to
   *Decisions made* — and stop. Do not roll into the next stage.

Stages are independent. Order below is recommended, not required.

**Closed 2026-08-06 — all nine stages resolved or declined.**

Stages 1, 2, 4, 5, 6, 7, 8 and 9 are **done**; Stage 3 was **declined**. The
`/reconcile` defect this campaign found is **fixed** (and was three defects,
not one — see its section). Every completion criterion is met.

The file is kept rather than removed per ADR-042 because it has been retired
once already (`41319528`) and un-retired the same day (`af3f9dcf`) when the
next verification run produced two more stages. Three times running, the
campaign's own verification found that the things verifying it were lying —
Stage 7 (`globalThis`), Stage 8 (five confirm sites, not two), Stage 9 (state
outside the sandbox). Retiring it is the owner's call.

The through-line of the last three stages is one sentence: **state outside
the isolation mechanism reports success until the order changes.** In Stage 7
it was `globalThis`; in Stage 9 it was `:persistent_term`, which the Ecto
sandbox has no reach into and no opinion about.

Two things changed under the whole campaign near its end, and both are worth
knowing before you trust an older sentence in this file:

* **Stage 7 changed what "precommit green" means.** The JS runner now covers
  `assets/js/` whole rather than a hand-listed pair of directories, so
  `mix precommit` and CI run the same 620 tests across 29 files instead of
  564 across 24. Stages 1–6 were verified against the narrower claim.
* **Stage 7's own diagnosis was half wrong when written**, and Stage 8's
  planned shape was wrong in a different way. See errors 9 and 10 in the
  ledger — the two sharpest entries in it.

**Every stage's facts were verified on 2026-08-06 when it was written**, not
inherited from the audit. Every figure carries the command that produced it —
including one that shrank a stage: "8 failing tests" is **one** root cause,
not eight. Which was true, and still not the whole story.

**Stage 3 was declined, not deferred** — the console stays out of the input
system deliberately (backtick already opens it; the input system would take
the arrow keys and Escape on a log-reading surface). Don't re-open it as
unfinished work, and don't read `/console`'s missing nav config as a gap.
Note that Stage 7 *does* touch console JS — its hook tests. That is not a
re-opening of Stage 3; the console's exclusion from the **input system** is
unrelated to whether its **hook** has working tests.

Stale memories to drop before you start:

* `library.ex` is **not** one big file. Stage 1 split it into 18 modules;
  `MediaCentaur.Library`'s moduledoc is a table naming which module owns
  which concern, and it is the fastest way back in.
* Test policy changed in Stage 4. `Repo` **writes** in tests are banned
  (MC0023) but `Repo` **reads** are fine; `=~` on HTML *attributes* is
  banned (MC0024) but `=~` on user-visible copy is fine and expected. Use
  `TestFactory.force_attrs/2`, `backdate/3`, `force_state/2`,
  `force_where/2` for setup the public API refuses to produce.
* Lookups follow one contract, enforced by MC0022: `fetch…` returns a
  tuple, `get…` returns nil-able, `…!` raises.
* Stage 3 left **no code on `main`** — built to working code to prove the
  design, then reverted in full. Don't go looking for half-applied console nav.
* **`Topics` is no longer names-only.** Stage 5 gave it `publish/2`,
  `subscribe/1`, `unsubscribe/1`, and it is now the only module naming
  `MediaCentaur.PubSub` (MC0025). Publishing goes through the owning
  context's `Events.broadcast/1` where the topic has one — `Library`,
  `Playback`, `Review`, and `Library.Progress`. **Do not add a
  `Phoenix.PubSub` call**; Credo will reject it.
* **`SettingAware` already exists.** Stage 6's boolean-setting bullet reads
  as though nothing is shared. The web-side mechanics were extracted long
  ago; see that bullet's correction before costing the item.

**Two things carried forward that do not belong to Stage 6**, and do not
hold the campaign open either:

* **MC0023's grandfather list** — 23 test files still building state with an
  inline `Repo` write because their schema has no `TestFactory` builder. The
  check makes the debt visible and stops it growing. Add the builder,
  convert the file, remove the entry; the list may only shrink. If it is
  still 23 in a few months, that is the signal it needed a stage of its own.
* **Per-context event conversion** (ADR-060) — on next touch, never a sweep.
  `Review` is the worked example to copy.

## Fourteen counting errors, one campaign — and what they cost

Every stage but one recorded at least one figure it later disproved. The
sequence is the campaign's most durable output, so it is stated in full:

| # | Stage | The error |
|---|---|---|
| 1–2 | 2 | A hatch count corrected twice before it was right |
| 3 | 4 | `Repo\.[a-z_]*(` cannot match a `!`, hiding every bang variant: ~~301~~ → **450**; and "345 markup assertions" was really **14**, the other 298 asserting user-visible copy the amended policy permits |
| 4 | 4 | A new Credo check caught eight `Repo.update_all` sites the same grep had missed |
| 5 | 3 | Every number **correct**, the stage still built on a false premise — nobody checked whether `/console` ran the input system at all |
| 6 | 5 | MC0012 and MC0013 had **never been able to fire** — verified 0 issues against a real violation |
| 7 | 6 | The `/reconcile` nav defect was **three** defects. The missing config was one; `data-nav-default-zone` also named a context instead of the layout key, and the shared ReviewTabs strip was dead on `/review` too |
| 8 | 6 | `clear_database`'s native confirm: the bullet said **1** site, the stage's own correction said **2**, the repo has **5** |
| 9 | 7 | "One root cause" was right and the cause named was wrong. The stub did not lack `dispatchEvent`; `console.test.js` did not own its `window` at all. Run alone it passed **17/17** — the 8 failures appear only when `log_tail.test.js` loads first and leaves its own `window` on `globalThis` |
| 10 | 8 | Every option the stage tabled was a *kind of dialog*, because it asked "which idiom" — which silently assumed all five sites deserved one. The owner's answer was **two of them deserve none.** The count of five was right for the third time running; the question asked of it was wrong |
| 11 | 9 | "Main passes at the same seed" read as exoneration and was not — main had 12 fewer tests, so the seed interleaves differently. Holding the count constant (five inert tests) reproduces it on untouched main |
| 12 | 9 | The named cause was wrong again, and again a probe caught it: `activity_empty?` is gated on a `:persistent_term` capability cache, which is a perfect suspect and **innocent** (`download_client_ready=true`, key `:__unset`). The leak is a GenServer nobody resets |
| 13 | 9 | …and *that* was wrong too. `QueueMonitor` is **not started under `:test`** (`pubsub_listeners(:test) → []`), so no GenServer state survives anything. The leak is its `:persistent_term` cache, written by the test file that starts its own monitor. Option 3 as tabled — reset the stateful processes — would have fixed nothing |
| 14 | 9 | The stage's own repro, "1 failure, every time", produces **0 failures** on the tree it was measured on. A seed lottery is a function of the module *list*; naming the five inert tests differently is enough to dissolve it |

The lesson accreted in three passes:

1. **A check you can run beats a number you wrote down.** (Errors 1–4.)
2. **A number beats nothing only if you also checked the assumption
   underneath it.** (Error 5 — counting what is *missing* from a page says
   nothing about whether the thing it plugs into is *present*.)
3. **A check counts only if you ran it against a violation.** (Error 6 — an
   unexercised check is not a weaker guarantee than a counted number, it is
   a *false* one, because it reports success. Neither check had a test.)

Two more, both paid for:

* **Derive costs from the tool, not from a table.** Stage 2's real
  dependency lists came from removing each hatch and reading the compiler —
  that is what surfaced the `in:`-side cost the stage had not costed at all.
* **Read the comment beside the constant before theorising about it.**
  Stage 4 reasoned its way to "something held a write lock for over ten
  seconds" when `config/test.exs` documented that exact failure mode three
  lines above the timeout it was reasoning about.

And two more were *avoided* the same way, both by running commands the
document had merely asserted:

* Stage 5's stated verification criterion ("the literal grep should read 0")
  is impossible — `application.ex` must name the PubSub server to start it.
  Caught while writing the criterion, by running it.
* Stage 6's boolean-setting bullet reads as though nothing is shared across
  the eight modules. `MediaCentaurWeb.Live.SettingAware` has been the shared
  abstraction for the web half all along, and the four traits cannot fully
  collapse because each needs a unique literal atom by design. Its *285
  lines* figure is right; its *remedy* covers 175 of them. Reading the code
  the bullet describes is what surfaced it — and, separately, that one of
  the four flags has the opposite polarity, which a naive macro would have
  silently flipped.

That last one is the pattern worth naming: **a correct count can still
recommend the wrong fix.** Stage 6's line count survived verification and
its conclusion did not.

Stage 6 then produced the sharpest version of it twice more, so it earns a
fourth clause:

4. **A count answers "how many", never "which fix".** Both of Stage 6's
   remaining bullets were counted correctly and prescribed wrongly.
   `clear_database` proposed converting a native confirm to `ModalShell` —
   but the repo already has *two* confirmation idioms and *five* native
   holdouts, so the change is a decision, not an edit. The cast grid
   proposed "cap the rendered window, or pass the list as a `data-`
   attribute" — the first silently breaks the filter's only purpose, the
   second puts a second copy of the card markup in JavaScript. In both
   cases the number was right and the sentence after it was not.

Stage 7 then added the fifth, and it is the sharpest of them:

5. **Reproduce the failure before naming its cause.** Stage 7's diagnosis was
   written from reading a stack trace: eight identical `TypeError`s pointing
   at `console.js:66`, therefore the stub is missing `dispatchEvent`.
   Plausible, specific, wrong. Running `console.test.js` **by itself** — one
   command, never run — gives **17 pass, 0 fail**. The stub was never the
   variable; the file simply does not own its `window`, and inherits whichever
   one the previously loaded test file left on `globalThis`. Same trap as
   error 5, one level down: a correct observation about what is *broken* said
   nothing about *why*, and reading the trace felt enough like reproducing to
   skip actually doing it.

Stage 8 supplied the sixth, and it is the one that generalises furthest:

6. **Check the question before you answer it.** Stage 8 tabulated five sites,
   counted them correctly for the third time, and offered three options —
   every one of them a *kind of dialog*. The word "idiom" in the question had
   quietly encoded the assumption that each site needed one. The owner picked
   none of the three: *"remove excluded dir and history row require no
   confirmation."* Clause 4 says a count never tells you which fix. This is
   one level up again — **a well-posed question can still be the wrong
   question**, and the tell is that every option shares a premise nobody
   stated. Ask what the options have in common; that is where the assumption
   is hiding.

Stage 9 then paid clause 5 twice more in one sitting, which is worth naming
as a seventh:

7. **A control group needs the same shape, not just the same code.** "It
   fails on my branch, it passes on main" is only evidence if everything else
   is held constant. It was not: the branch had 12 more tests, and test count
   changes the interleaving as surely as a code change would. Padding main to
   the same count reproduced the failure on untouched code. The general form:
   **when you compare two runs, list what differs besides the thing you are
   testing** — and if the answer is "nothing, except…", that is the variable.

Stage 9 then produced the eighth, and it is the one that explains why
clause 5 kept failing to save anyone:

8. **A measurement is a number and a label, and only the number is
   measured.** The probe printed `queue_monitor_items=3`. The three was
   real, and every sentence written after it rested on the label —
   *QueueMonitor*, therefore a GenServer, therefore reset the GenServer.
   The module was not running at all, and `pubsub_listeners(:test) → []`
   was one grep away throughout. Clause 5 says reproduce before naming the
   cause; Stage 9 *did* reproduce and named it wrong anyway, because the
   reproduction confirmed the number and the label rode along unexamined.
   **When a probe names a module, check that the module is running.**

And one thing that went the other way, worth recording because it is the
cheap move that keeps paying: **measure before you decide whether to
care.** The cast-grid bullet read like nitpicking until it was rendered —
1.6 MB of HTML for one series. That number is what turned a droppable
polish item into the stage's most valuable change. The measurement took two
minutes and inverted the decision.

## Status

**Stages 1, 2, 4, 5, 6, 7, 8 and 9 done; Stage 3 declined** (all
2026-08-06). Every completion criterion is met. `mix precommit` green after
each stage — and since Stage 7, that phrase covers the JS tree. Last run:
**5787 tests, 0 failures** plus **620 JS across 29 files**. Since Stage 9
that sentence is worth slightly more than it was: the term store no longer
carries one test's writes into the next, so a green run is less of a
statement about the seed than it used to be.

* **Stage 1** — `library.ex` 2779 → 127 lines across six commits
  (`5b2d3510`…`f91f61ce`); 18 modules; the 21 `# ---` dividers are gone.
* **Stage 2** — two of three Boundary hatches closed, the third documented
  as a permanent, decided exception.
* **Stage 3** — declined. The console is deliberately outside the input
  system. Implemented far enough to prove the design, then reverted in full.
* **Stage 4** — two overreaching policies reconciled with practice, behind
  **three** new Credo checks (MC0022–MC0024); five lookup-contract
  violations fixed, 40 test-setup sites converted.
* **Stage 5** — ADR-060; the `Topics` transport (132 sites, 71 files);
  `Review.Events` as the worked example; MC0025 and MC0026 added, and
  MC0012/MC0013 repaired after being found vacuous since birth.
  (commit `5328226f`)
* **Stage 6** — four of six items shipped, one was already shipped by Stage
  5, one dropped as an idiom decision the owner should make. Commits
  `d4178d76`, `3ceac88f`, `81a26c64`.
* **`/reconcile`** — fixed (`2e4aa4d7`), along with two further defects
  reading the page turned up. Not a stage; it was found here and finished
  here.
* **Stage 7** — both runners widened to `assets/js/`; the shared-global test
  harness that made the hook tests order-dependent replaced. 564 tests across
  24 files → **620 across 29**, 0 failures, and CI now runs what precommit
  runs.
* **Stage 8** — confirmations graded by consequence: two sites dropped theirs,
  one arms in place, `clear_database` gets a persistent modal. MC0027 makes
  `data-confirm` a violation, with the console exempted on the record.
  (commit `7cb11a61`)
* **Stage 9** — the leak was a `:persistent_term` cache, not the GenServer
  the stage was named after (which never runs under `:test`).
  `GlobalStateSandbox` restores every app-owned term from a namespace-derived
  baseline before each `DataCase`/`ConnCase` test, resets two singletons, and
  fails a test when the supervision tree grows an unclassified child. Six
  files lost their private workarounds.

The 2026-08-05 sweep's Critical and Moderate-with-user-impact findings were
fixed and pushed before the stages began (see *Decisions made*); this
campaign is the tail.

## Two findings Stage 6 turned up — now Stages 7 and 8

Neither belonged to Stage 6 and neither held it open. Both are real, both
have their own stage below, and both had their facts re-verified when those
stages were written:

* **`assets/js/hooks/` is in no test run** → **Stage 7**, ✅ done. Failing
  since 2026-04-29 and invisible the whole time — and failing for a different
  reason than the one first written down.
* **Five `data-confirm` sites, not two** → **Stage 8**, ✅ done. The count went
  1 → 2 → 5, and the remedy turned out not to be an idiom choice at all — two
  of the five needed no confirmation.

Stage 4 also chased an intermittent `(Exqlite.Error) Database busy` that
turned out to be a second `mix test` against the same SQLite file, not a
defect. Nothing to pick up.

## Decisions made

* `2026-08-05` — Four-audit sweep run (engineering / performance /
  documentation / design). 53 findings; 2 Critical (perf), 1 Critical
  (design).
* `2026-08-05` — Detail projection split: entity payload (`:cast`,
  `:crew`, `:seasons`, `:movies`, `:images`, `:external_ids`) stored
  once per entity in `:library_view_detail_shared` instead of once per
  row. **219 MB → 5 MB** on a 765-row library; per-row read 330 µs →
  4.7 µs. Full rebuild now emits one `{:library_view_updated, :detail,
  :all}` instead of 765 per-row messages; availability flips patch
  `:present?` in place instead of a 276 ms rebuild. (commit `f1050227`)
* `2026-08-05` — Watch-history delete gated with `data-confirm` and
  made keyboard-reachable; duration column moved to the app-wide
  `Xh Ym` vocabulary; `.text-on-image` and `.image-scrim-*` extracted.
  (commit `a0668da7`)
* `2026-08-05` — 35 unreferenced public functions deleted, 3 narrowed
  to `defp`. (commit `18950c88`)
* `2026-08-06` — `ex_code_view` path dependency removed; it made
  `mix setup` fail on any fresh clone, breaking CONTRIBUTING's own
  documented setup for every external contributor. Its six agent
  scripts retired; `viz-screenshot`'s general `--url` mode survives as
  `~/scripts/agents/page-shot`. (commit `7c91a459` + dotfiles sync)
* `2026-08-06` — ADR-012 citations retargeted. The record was retired
  on purpose in `9e3fd7a4`; 15 sites still cited it and all but three
  meant **UIDR-012**, a different record sharing a number. ADR-042
  amended: permanent documents must never *link* a campaign, only name
  it — the removal-on-completion rule guaranteed dead links, and five
  had already accumulated. `decisions/README.md` is now a generated
  index. (commit `7c91a459`)
* `2026-08-06` — Continue Watching was rendering **empty**, not merely
  short: the SQL `limit` ran before the unfinished test. Both halves of
  "in progress" now run in SQL. `Playback.SessionRecovery` (boot path,
  zero prior test references) covered. (commit `914e94c9`)

* `2026-08-06` — **Stage 1 complete.** `library.ex` 2779 → 127 lines
  across six commits; 18 new modules plus merges into five that already
  existed. The remaining facade is `subscribe/0`, the change broadcast,
  three HomeFeed delegators, and a moduledoc table naming where each
  concern lives.

  The facade policy landed *more* aggressively than agreed: the plan was
  to keep delegators for functions with 3+ call sites, but the
  `Containers` collapse changed the shape of nearly every remaining
  function (`create_tv_series!/1` → `Containers.create!(:tv_series, …)`),
  so a delegator would have preserved the old name and defeated the
  collapse. Call sites moved instead — ~93 for containers, ~27 for
  progress, ~35 files for the file domain.

  Defects found and fixed during the move, beyond the planned ones:
  - `list_seasons_by_owner_id/1` and `list_seasons_for_tv_series/1` were
    byte-identical bodies — two public functions, one query.
  - `list_images/2` and `logo_urls_for_entities/1` survived in
    `library.ex` after the Image extraction, leaving two implementations
    each with only one reachable.
  - `find_by_external_id/2`'s spec named
    `ExternalIds.owner_type()`, a type that never existed; it compiled
    only because Elixir doesn't resolve remote types eagerly.
  - `MovieSeries.update_changeset/2` and `VideoObject.update_changeset/2`
    had zero callers, unreachable behind missing per-type wrappers. The
    dispatched `Containers.update/2` makes them reachable.
  - The owner-key translation had **four** implementations (three in
    `library.ex`, one independently written in the test factory); all
    now route through `Library.OwnerRef`.
  - `link_file/1` and `create_extra_file/1` were the same function apart
    from the schema; now one `upsert_by_path/2`.
  - The two progress-summary builders differed only in grouping key;
    their shared tail is now one `summarise/2`.

  Deliberately **not** done: the `@owner_types` lists on the sidecar
  schemas still each declare their own `Ecto.Enum` values. `OwnerRef`
  now owns the translation and could own those too, but changing an
  `Ecto.Enum` values list is a schema-level change with migration
  implications and belongs in its own commit.

* `2026-08-06` — **Stage 2 complete.** Two of the three Boundary hatches
  closed (`Status`, `Diagnostics`); the third (`Showcase`) kept and
  documented as a decided permanent exception.

  **Owner decision — `Showcase` stays hatched.** Seeding is the one job
  that legitimately reaches past every facade: 45 cross-context
  references over eleven contexts, four `Acquisition` schema structs the
  context deliberately does not export, and six direct `Repo` writes that
  exist to force states (a mid-flight pursuit, a backdated watch event)
  the public APIs correctly refuse to produce. Closing it would mean
  `Acquisition` exposing a seeding API whose only caller is the demo
  instance — a real widening of the production surface to satisfy a
  declaration on a module nothing in production loads. The second open
  question (`Acquisition` proper vs a dev-only `Acquisition.Seeds`) is
  moot as a result. `WatcherStatus` already set the precedent for a
  documented hatch.

  **Owner decision — the 62-name `Library` `exports:` list is deferred.**
  Recorded as a question for later rather than folded into this stage;
  Stage 2 added only the two names it actually needed.

  Corrections to the recorded evidence: the hatch count is **30**, and
  neither 26 nor 31 was ever produced by the command the file recorded
  (`grep -rc` prints one line per searched file). The stage also
  under-scoped itself — it costed out-refs only, but re-enabling `in:`
  required `Status` to gain an `exports:` list and `MediaCentaurWeb` to
  declare a `MediaCentaur.Status` dep it had never needed.

* `2026-08-06` — **Stage 3 declined.** The console stays out of the input
  system on purpose. It already has a keyboard route in (backtick opens the
  drawer anywhere), and on a log-reading surface the input system would take
  ownership of the arrow keys, Escape and BACK — the keys you want left alone
  while reading and selecting log text. The stage's framing ("unreachable
  without a mouse") treated a deliberate design as an omission.

  The attempt was carried to working code first, then reverted in full;
  nothing is on `main`. It surfaced two durable facts. First, **`/console`
  mounts no `#input-system` hook at all** — the hook lives on `Layouts.app/1`
  / `Layouts.input_system_root/1` and `ConsolePageLive` uses neither, so
  arrow keys never leave `<body>`. That absence is now the enforcing
  mechanism for this decision, not a bug. Second, the checklist's
  `data-nav-default-zone="console_tabs"` was wrong — that attribute names the
  **layout key**, not a zone.

  **Unrelated defect found on the way:** `/reconcile`'s navigation is dead.
  It declares a behavior, two zones and `data-nav-item` on every row, but
  `config.js` has no `reconcile` entries of any kind, so `buildNavGraph`
  returns `{}`. Unlike the console this is not deliberate — the page is
  structurally identical to `review` and wants the same three-line layout.
  Recorded in Stage 3 for whoever picks it up; it is not a Stage 3 obligation.

* `2026-08-06` — **Stage 4 complete.** Owner chose *amend the policies
  **and** enforce them*, and *fix the naming sites **and** add a check* —
  so all three amended rules now have code behind them (MC0022, MC0023,
  MC0024) rather than prose in a skill file.

  **Both of the stage's headline numbers were wrong.** `Repo.*` in
  `test/` was 450, not 301 (the recorded command can't match a `!`, so
  every bang variant was invisible); 114 of those are writes. The `=~`
  figure was worse than wrong, it was misleading: of 312 assertions with
  a literal right-hand side, only **14** were structural markup — the
  rest assert user-visible copy, which the amended policy permits. There
  was never a 345-site problem. A third miscount surfaced mid-stage when
  MC0023 caught eight `Repo.update_all` sites the stage's grep had also
  missed. Three counting errors in one stage, in a file that already
  carried the "run the command" lesson twice: the lesson is not that
  greps need care, it is that **a check you can run beats a number you
  wrote down**.

  **Contract:** five violations fixed, three of which the campaign never
  named — MC0022 found `Acquisition.Pursuits.get/1`, `Pursuits.Units.get/1`
  and `Plans.get/1` all returning tuples. `Settings.get_by_key/1` was
  reshaped to `Entry.t() | nil` across ~32 sites: it returned `{:ok, _}`
  in every branch, so the tuple could not fail and carried no
  information. Grandfathering it would have exempted the biggest
  violator on day one.

  **Scope deliberately widened twice** rather than accept a grandfather
  entry: the `Settings` reshape, and `TestFactory.force_where/2` (added
  so eight bulk-`update_all` setup sites had somewhere to go instead of
  putting six more files on MC0023's backlog). MC0022 and MC0024 ship
  with **zero** exemptions; MC0023 carries 23 files whose schemas have no
  factory builder yet — that list is the rollout backlog and may only
  shrink.

  **A `Database busy` scare, resolved as a non-issue.** Two runs failed
  on `settings_entries` inserts. Bisecting cleared the stage (`main` 4/4
  clean, and none of the four new test files reproduced it), but the
  follow-up diagnosis — "a writer held a lock past the 10 s
  `busy_timeout`, something is stuck" — was wrong. `config/test.exs`
  documents this exact mode at the line setting that timeout, and both
  failures fall inside the window of two commits made on `main` during
  the session: a second `mix test` against the same SQLite file. Read the
  comment beside the constant before theorising about it.

* `2026-08-06` — **Stage 5 complete, and the campaign with it.**
  [ADR-060](../decisions/architecture/2026-08-06-060-event-publication-idiom.md)
  settles both open questions the way the owner chose: typed structs are
  the target **in the `Library`/`Playback` shape**, and the `Topics`
  transport landed alongside it.

  The stage's framing had the cost wrong, and correcting it is what made
  question 1 answerable. `Pursuits`' 20 files are not what the idiom
  costs — they buy **persistence** (`define.ex` generates
  `to_payload/from_payload` for a JSONB column so a pursuit replays cold
  from the DB). The idiom as `Library` and `Playback` practise it is *one
  file per topic*: nested structs in a single `events.ex` with a
  `broadcast/1` whose heads enumerate the message set. The migration unit
  is one file, not twenty — so "expand it" stopped being the expensive
  answer it looked like.

  **The transport landed whole**, not on-next-touch: 132 call sites in 71
  files, mechanical and idiom-agnostic. `Topics.publish/2`,
  `subscribe/1`, `unsubscribe/1` are now the only place naming the PubSub
  server. Topic names stayed zero-arity functions rather than atoms — a
  misspelt `Topics.review_updates()` fails to compile, which is the whole
  reason the module exists.

  **`Review` is the worked example**: four typed payloads, one
  chokepoint, subscribers converted in the same commit. Two of its four
  messages were positional 3-tuples (`{:group_error, key, message}`) —
  the exact shape where a publisher can swap two same-typed arguments and
  no subscriber can tell.

  Two things the stage did not anticipate:

  - **Boundary caught a real consequence.** Typed payloads turn an
    implicit runtime coupling into a declared compile-time one:
    `Status.Views.Overview` and `ShellBadges` name `Review`'s structs, so
    `Review`'s boundary had to export them. Bare tuples had hidden that
    dependency completely. Same precedent as `Library`, which already
    exports `Events.EntitiesChanged`.
  - **The migration nearly stopped at 80% — on itself.** MC0012 and
    MC0013 match `Phoenix.PubSub.broadcast` AST. Converting every call
    site to `Topics.publish` would have left both checks unable to fire,
    silently. They now match both spellings.

* `2026-08-06` — **A sixth counting error, and a new kind: MC0012 and
  MC0013 never worked.** Not stale — *never able to fire*, from the day
  each was written.

  Both matched a payload of `{tag, _, _}`, a **three**-element AST node.
  A two-element tuple literal like `{:entities_changed, event}` quotes to
  the plain 2-tuple `{:entities_changed, {:event, _, nil}}` and matches
  neither clause. `:entities_changed` is the *only* tag MC0013 guards,
  and every current playback payload is likewise a 2-tuple. Verified by
  running each check against a hand-written violation: **0 issues**,
  both. Neither had a test.

  So the campaign's own lesson needed one more clause. "A check you can
  run beats a number you wrote down" — **but only if you ran the check
  against a violation.** An unexercised check is not a weaker guarantee
  than a counted number; it is a *false* one, because it reports success.
  Both checks now share one tested matcher
  (`credo_checks/event_chokepoint.ex`) covering 2-tuple and 3+-tuple
  payloads and both call spellings, with 16 cases pinning it. MC0026
  reuses it for `review:updates` rather than hand-rolling a third copy.

* `2026-08-06` — **Stage 6 complete, and the campaign closed.** Four items
  shipped (`d4178d76`, `3ceac88f`, `81a26c64`), one was already shipped by
  Stage 5, and one — the `clear_database` confirmation — was **dropped** as
  the stage's rules allow. It is five native `data-confirm` sites rather
  than the one the bullet named or the two the stage's own correction found,
  and the repo already has two themed confirmation idioms, so "use
  ModalShell" is a decision rather than an edit. That belongs to the owner
  and to its own stage, not to a list headed *no discussion needed*.

* `2026-08-06` — **The `/reconcile` defect was three defects** (`2e4aa4d7`).
  Beyond the missing config: `data-nav-default-zone` named a context instead
  of the layout key — the precise trap Stage 3 had already written down —
  and the shared `ReviewTabs` strip was unreachable by keyboard on `/review`
  as well, which nobody had noticed because the rest of that page works.
  Held by `config_coverage.test.js`, which derives its expectations from the
  templates rather than listing pages by hand, because a hand-written list
  (`index.test.js`, five layouts of twelve) is what let this through.

* `2026-08-06` — **Two more counting errors, and the fourth clause of the
  lesson.** Both of Stage 6's remaining bullets counted correctly and
  prescribed wrongly: `clear_database` (1 → 2 → 5 sites, wrong remedy) and
  the cast grid, whose two suggested fixes would have silently broken the
  filter or duplicated the card markup in JavaScript. **A count answers "how
  many", never "which fix".**

  The counterweight is cheap and kept paying: **measure before deciding
  whether to care.** The cast-grid bullet read like nitpicking until it was
  rendered — 1.6 MB of HTML for one series, to display 24 cards. Two
  minutes of measurement turned the stage's most droppable item into its
  most valuable one.

* `2026-08-06` — **Found, not fixed: `assets/js/hooks/` is in no test run.**
  `mix precommit` runs `assets/js/input/` + `assets/js/__tests__/`; CI runs
  `assets/js/input/` alone. Neither covers `assets/js/hooks/`, where 8
  Console-hook tests fail today — confirmed on a clean tree, so they
  pre-date this campaign and have never been seen to fail. Error 6's shape
  one level up: the suite reports success because the failing tests are
  never run. → **Stage 7.**

* `2026-08-06` — **The campaign reopens on two stages rather than closing.**
  It was briefly marked complete and its file retired per the
  removed-when-complete convention (`4235948b` records it, `41319528`
  removed it, reverted in `af3f9dcf`). That was wrong: Stage 6's two
  findings are not loose ends to file away, they are work with owners and
  shapes, and a memory note is a worse home for them than the campaign that
  found them. They are now Stages 7 and 8.

  Their facts were verified when the stages were written, not carried over
  from the finding. That paid immediately: **"8 failing tests" is one root
  cause**, not eight — every failure is the same missing `window.dispatchEvent`
  on a test stub that never followed `358bab78` (2026-04-29). The stage got
  smaller for being checked, which is the opposite of the direction this
  campaign's numbers usually moved, and worth recording for that reason.

* `2026-08-06` — **Stage 7 done. The JS runners cover a tree, not a list.**
  `mix test.all` and CI both run `bun test assets/js/` — 620 tests across 29
  files, up from 564 across 24, and the two now make the same claim. A path
  list is a thing to maintain; a tree is not, and the maintenance is exactly
  what failed here.

* `2026-08-06` — **Hook tests install their browser globals unconditionally,
  per test** (`assets/js/test_support/dom_stubs.js`). The guarded idiom —
  `if (typeof window === "undefined") { globalThis.window = ... }` — is
  banned by the module's header comment rather than by a check, because it is
  a two-file problem and a check would cost more than it saves. The idiom is
  what made the hook tests order-dependent: whichever file loads second runs
  against the first one's stub.

  **It produced a false red and a false green from the same line.** Red when
  `log_tail.test.js` loaded first (8 `TypeError`s); green when
  `console.test.js` ran alone, where an overridden `addEventListener` and
  bun's native `dispatchEvent` are two registries that never meet, so the
  repin dispatch went nowhere and 17 tests reported success. That is the
  campaign's error-6 lesson — *an unexercised check is a false guarantee, not
  a weak one* — arriving in test-harness form.

  The stage's own written diagnosis was a casualty of the same thing: it was
  derived from a stack trace, and the one command that would have falsified
  it (running the file alone) was never run. Logged as error 9, and it earned
  the ledger its fifth clause: **reproduce the failure before naming its
  cause.**

* `2026-08-06` — **Stage 8 done. Confirmations are graded by consequence, not
  chosen per site.** Trivially reversible → nothing; costly but recoverable →
  arm the control in place; irreversible *and* unbounded → a persistent
  `<.modal>`. Today that is: nothing for removing an excluded directory or a
  watch-history row, Confirm/Cancel for refreshing the image cache, and a
  modal for `clear_database`. **MC0027** makes `data-confirm` the violation,
  since a written-down policy drifts and a checked one does not (Stage 4).

  The owner's answer refused the question as posed. All three options offered
  were kinds of dialog; the reply was that two sites need none. Recorded as
  error 10 and clause 6 — **check the question before you answer it**, and
  look for the premise every option shares.

  Two judgement calls inside it, both made by reading the page rather than
  the plan: the in-place idiom copies the media-directory rows three rows up
  (Confirm/Cancel), *not* the detail panel's label-flip, because two
  arm-in-place shapes on one screen is the drift the stage exists to remove;
  and the planned "one shared component" was dropped once the modal had a
  single caller. What is shared is the rule, and MC0027 is where it lives.

* `2026-08-06` — **"Confirm it on main" is not a valid exoneration if your
  branch changed the test count.** Stage 8's final run failed one
  `incoming_live_test.exs` empty-state assertion — a file it does not touch.
  Main passed at the same seed, which looked like exculpation and was not:
  main had 12 fewer tests, so the same seed produces a different
  interleaving. The honest check holds the count constant. Padding clean
  main with **five inert `assert 1 == 1` async tests** reproduces the failure
  at seed 508425 every time.

  Five tests that assert nothing cannot break anything, so the defect is
  pre-existing. **It became Stage 9** rather than a backlog note, once
  chasing it produced a measured mechanism: `Downloads.QueueMonitor` holds
  its state across tests and three stale queue items render as orphans. Same
  class as Stage 7 — state outside the isolation mechanism.

* `2026-08-06` — **A wait predicate that unrelated copy can satisfy is a
  false green.** Stage 8's modal copy contains "video files"; two media-dir
  tests waited via `render_until(view, "video files")` for a debounced
  validation. The modal is always in the DOM, so the wait became a no-op and
  a form submitted before its debounce landed — failing in a test that
  touches nothing the change touched. The preview now has
  `id="media-dir-preview"` and both tests wait on the element. MC0024's
  principle (parse the document, don't substring the markup) applies to
  **waiting**, not only to asserting.

---

## Stage 1 — Split the `Library` context  ✅ **DONE 2026-08-06**

**Why first.** Every other Library-touching finding is downstream of
this file being too large to hold in one head. It is where 27 of the
35 dead functions lived, and where the `fetch_`/`get_` contract
inconsistency hides.

**Evidence.** `lib/media_centaur/library.ex` is 2779 lines with 21
`# ---` sections, each a distinct domain:

    TVSeries · MovieSeries · VideoObject · PlayableItem ·
    Search-index source · WatchedFile · FileMediaInfo · Image ·
    ExternalId · Movie · Extra · ExtraFile · Season · Episode ·
    WatchProgress · HomeLive facade

The repo's own `coding-guidelines` skill names this exactly: *"`# ---`
section dividers separating distinct domains — that's a smell, and the
new code is the cheapest moment to fix it."*

**Reconciled 2026-08-06.** The facts hold (2779 lines, 21 sections, 163
public / 63 private functions), but two section headers understate their
contents:

* **`FileMediaInfo`** (612 lines, 28 pub / 20 priv) is five domains, not
  one: media-info probing · watched-file path queries · `relink_moved_files`
  · `populate_content_urls` (view shaping) · `resolve_presentable` ·
  `load_modal_entry` (detail-modal builder).
* **`HomeLive Facade`** (343 lines, 11 pub / 14 priv) is three lines of
  actual delegators, then `stats/0` plus ~330 lines of progress-record
  and progress-summary aggregation that has nothing to do with the home
  page.

Call sites: **189** in `lib/`, **471** in `test/`. The `lib/`
distribution is lopsided — 62 of 104 distinct functions have exactly one
caller, 84 have ≤2, only 6 have ≥5.

**Approach (agreed 2026-08-06).**

* **Cadence:** one campaign of N mechanical commits, precommit green per
  commit. Split-on-next-touch was already tried implicitly — `HomeFeed`
  and `EntityCascade` came out and the file is still 2779 lines, so it
  demonstrably does not converge.
* **Facade:** delegate only functions with 3+ call sites (~20). For the
  84 called once or twice, move the call site and delete the delegator.
  A facade of 163 delegators for an API where 60% of functions have a
  single caller is a phone book, not an entry point.
* **Naming:** plural sibling modules, following the existing
  `ExternalId` (schema) / `ExternalIds` (queries) precedent. Schema
  modules here are lean — changesets and pure helpers — and stay that
  way; folding queries into them would make every schema moduledoc say
  "the shape *and* the queries."
* **Stage 4 stays separate.** Only five functions are affected by the
  naming unification and Stage 4 also carries policy rewrites unrelated
  to the split. Renaming while moving makes no commit reviewable as a
  pure move.

### Greenfield pass (`unify_design`, 2026-08-06)

**Core idea.** Every operation in `library.ex` acts on an *addressable
library entity* — `(type, id)` — or on data hanging off one. The
codebase already knows this in pieces: `PlayableItem` (canonical leaf
identity, Schema v2 Phase 2), the `(owner_type, owner_id)` discriminator
on four sidecar tables, `TypeResolver`, `EntityShape`. What is left in
`library.ex` is the layer that never got told.

**Module map — organised by role, not by table.**

| Role | Modules |
|---|---|
| Records | `Containers` (4 types, dispatched) · `Seasons` · `Episodes` · `Extras` · `PlayableItems` |
| Files | `Files` (WatchedFile **+** ExtraFile) · `MediaInfo` · `Relink` |
| Progress | `ProgressRecords` (WatchProgress **+** ExtraProgress **+** aggregation) |
| Sidecars on `(owner_type, owner_id)` | `Images` · `ExternalIds` · `MediaTrackOverrides` |
| Derived / read | `SearchIndex` · `Stats` · `ContentUrls` · `ModalEntry` |

Merges into modules that already exist: `ExternalId` (225L) →
`Library.ExternalIds`; `ChangeEntry` (25L) → `Library.ChangeLog`;
`resolve_presentable` family → `Library.PresentableQueries`; `Helpers`
(87L, all private) → `Library.Helpers`; `relink_moved_files` family →
new `Library.Relink`, pairing with the existing `Library.MoveMatcher`.

`ProgressRecords` is named to avoid colliding with both the
`WatchProgress` schema and `Library.Progress` (the ETS projection API);
it is the DB side. `ModalEntry` and `ContentUrls` are view-shaping, not
queries, but are called from the context, so they stay at `Library.*`.

**Containers collapse.** The TVSeries / MovieSeries / VideoObject /
Movie sections repeat the same eight-function CRUD shape four times
(~200 lines of near-duplicate). They collapse into one type-dispatched
`Library.Containers` — `fetch(:tv_series, id)`, `create!(:movie, attrs)`
— mirroring the `(owner_type, owner_id)` discriminator the schema
already uses and the existing `Library.TypeResolver`. `Containers` also
becomes the owner of *what a container is*: the type list is currently
hand-written in `ExternalId` and implicit in `TypeResolver`'s
try-each-table order.

### Incoherences and their disposition

**(a) `WatchProgress`'s API speaks a schema that no longer exists — fix
in Stage 1.** Schema v2 Phase 2 Task C collapsed three FKs into one
`playable_item_id`; the schema has exactly one FK. The API still offers
`fetch_watch_progress_by_fk(:movie_id, id)` — a column name that does not
exist, translated to `(:movie, id)` on the first line of the body — and
three `find_or_create_watch_progress_for_{movie,episode,video_object}`
that accept "the legacy `:movie_id` key" and then
`Map.drop([:movie_id, :episode_id, :video_object_id])`. That is a
compatibility layer for a completed migration. Converges to
`ProgressRecords.fetch_for_container/2` and
`find_or_create_for_container/3`; the only real per-type difference —
canonical position (`Movie.position` / `Episode.episode_number` / `1`) —
moves to `PlayableItems.canonical_position/2`. 12 lib + 15 test sites.

**(b) Three container-type dispatches for progress, three signatures —
fix in Stage 1.** `fetch_progress_for_container/2`,
`find_or_create_watch_progress_for_container/4`, and
`list_progress_records_for_container/2` (filed 500 lines away under
"HomeLive Facade"). Same idea, three shapes, two sections. Free once (a)
lands.

**(c) `MediaTrackOverride` owner types — fix in Stage 1.**
`[:tv_series, :movie]` excluded `:video_object` with no stated reason; a
standalone video's remembered track selection is the same use case as a
movie's. Add `:video_object`.

**(d) `Extra` is a parallel playable — scheduled convergence, not now.**
`ExtraFile ∥ WatchedFile` and `ExtraProgress ∥ WatchProgress` are the
same seven operations twice, differing only in key (`extra_id` vs
`playable_item_id`). Converging means making `Extra` a `PlayableItem`;
the ExtraFile unification shipped in v0.95.4 and left this deliberately.
**Disposition:** group `Files` and `ProgressRecords` by role so both
parallels sit in one file each — the duplication becomes visible and
pressurised instead of filed apart. Convergence point: the next change
that touches Extra playback.

*Realised.* Grouping paid immediately on the file side: `link_file/1`
and `create_extra_file/1` turned out to be the same function apart from
the schema and collapsed to one `upsert_by_path/2`. On the progress
side it collapsed the public surface (`mark_completed/1` and
`mark_incomplete/1` now dispatch on the struct) but not the storage —
that still waits on Extra becoming a PlayableItem.

**(e) `ReleaseTracking.Item.@container_types` duplicates the container
universe across a context boundary — deferred to Stage 2**, which is
already the Boundary stage.

**(f) Generic CRUD macro — refused.** `create_X` / `create_X!` /
`fetch_X` / `destroy_X` / `destroy_X!` repeats across ~10 tables and a
`use Library.Record, schema: X` macro would collapse it. Refused: it
manufactures ~50 generated functions in a codebase that just deleted 35
unreferenced public functions (commit `18950c88`) and relies on grep to
find them. Codegen makes that class of dead code undetectable. The
`Containers` collapse is different — runtime dispatch on an explicit
atom, four real bodies to one.

**Target.** `Library` facade at 300–400 lines.

**Verification.** `mix precommit`; `mix boundaries`; the moduledoc of
each new module names *one* thing.

---

## Stage 2 — Close the Boundary escape hatches  ✅ **DONE 2026-08-06** (`3ff6a4ac`)

**Why.** [ADR-029](../decisions/architecture/2026-03-26-029-data-decoupling.md)
makes `use Boundary, deps: [...]` the canonical inter-context
dependency list. Where checking is off, that list is fiction.

**Evidence** (re-measured 2026-08-06, at the start of the stage).
**30** files declare `check: [in: false, out: false]` — not 26 (the
original text) and not 31 (the first reconciliation pass). Both earlier
figures came from `grep -rc`, which prints one line per *searched* file
including non-matches, so it never produced either number. The command
that does:

    grep -rl "check: \[in: false, out: false\]" lib/ --include='*.ex' | wc -l

Most are legitimate leaf utilities (`Format`, `DateUtil`, `Iso8601`,
`Log`, `Topics`, `Secret`, `Version`, `Repo`) or documented exceptions
(`WatcherStatus`, which exists to break a Boundary cycle and says so).
Three were not — and the real cost was derived by removing each hatch
and reading the compiler, not from the original table:

| Module | Out-refs | Contexts reached |
|---|---|---|
| `diagnostics.ex` | 18 | 2 — `ErrorReports` (+`Bucket`, `Incident`), `Playback` (+`Sessions`, `SessionRegistry`) |
| `status.ex` | 11 | 4 — `Acquisition`, `Library` (+`Completeness`, `ChangeLog`, `FilePresence`, `Stats`, `AbsenceSweeper`, `Availability`), `Maintenance`, `Review` |
| `showcase.ex` | 45 | 11, incl. 4 unexported `Acquisition` schema structs and 6 direct `Repo` writes across 1351 lines |

**What the original stage text missed.** It scoped the work as out-refs
only. Turning `in:` back on has its own cost: 10 references reach *into*
`Status` from the web layer, so `Status` needed its own `exports:` list
**and** `MediaCentaurWeb` needed `MediaCentaur.Status` added to its
`deps:` — that dep had simply never been declared, because `in: false`
made it unnecessary. Any future hatch closure should budget for both
directions.

**Resolved.**

* `Status` — hatch replaced with
  `deps: [Acquisition, Library, Maintenance, Review]` and
  `exports: [LibraryOverview, Views]`. Its moduledoc carried a
  "Boundary follow-up" note calling the hatch a stale holdover; the note
  is gone because the follow-up is done.
* `Diagnostics` — hatch replaced with
  `deps: [ErrorReports, Playback]`. Nothing references into it, so it
  needs no `exports:`. `ErrorReports` already exported `Bucket` and
  `Incident`; `Playback` exported `Sessions` but not `SessionRegistry`,
  now added.
* `Library` — `ChangeLog` and `Completeness` added to `exports:`. The
  original text named only `Completeness`.
* `Showcase` — **hatch kept, documented as permanent** (owner decision,
  see *Decisions made*). Its moduledoc now carries a *"Why the Boundary
  check is off, permanently"* section with the numbers and the reasoning,
  cross-referencing `WatcherStatus` as the existing precedent for a
  documented exception.

**Deliberately not done.** `Library`'s 62-name `exports:` list. It is
worth a look — most entries are schemas that callers need only to
pattern-match a struct, and the honest fix may be a narrower public
surface rather than a longer list — but it is a separate decision and
was explicitly deferred rather than folded into this stage.

**Observed, not acted on.** `lib/media_centaur/library/continue_watching_progress.ex:16`
declares `top_level?: true, check: [in: false, out: false]` — a
`Library.*` module that escapes the `Library` boundary. It is a pure
helper with no dependencies, so the hatch costs nothing today, but the
`top_level?: true` is unexplained and it is the only `Library.*` module
that does this.

**Verification.** `mix compile --force` reports **zero** warnings with
both hatches removed. Full `mix precommit` green — 5670 Elixir tests,
557 JS tests, credo clean, dependency-cruiser clean, sobelow clean.

---

## Stage 3 — `/console` keyboard and gamepad navigation  ❌ **DECLINED 2026-08-06**

**Owner decision: the console stays out of the input system, deliberately.**
The console is reached by keyboard already — backtick opens the drawer from
any page — and the input system would be actively *undesirable* on a
log-reading surface: it owns the arrow keys, Escape and BACK, which is
exactly what you want left alone while reading, selecting and scrolling
through log text. "Unreachable without a mouse" was the wrong frame; the
console is a mouse-and-backtick diagnostic surface by design, not a page
that was missed.

A declined stage is a valid outcome (see *Completion criteria*). The stage
was implemented far enough to prove the design before it was declined, and
then reverted in full — nothing from it is on `main`.

### What the attempt found before it was declined

Two facts worth keeping, because both outlive the decision:

* **`/console` never mounts the input system at all.** The `#input-system`
  hook lives on `Layouts.app/1` (and on `Layouts.input_system_root/1` for
  sidebar-less pages). `ConsolePageLive.render/1` uses neither — it returns a
  bare `<div class="console-fullpage">`, styled `position: fixed; inset: 0`.
  Probed live: `inputSystemRoot: false`, `sidebar: false`, no console drawer,
  and arrow keys leave `document.activeElement` on `<body>` through every
  press. So the stage's checklist could never have worked as written: zones,
  config and a behavior on a page with no orchestrator are inert. **This is
  now the mechanism that keeps the console out of the input system** — it is
  not an oversight to fix.

* **The checklist's `data-nav-default-zone` value was wrong.** It said
  `"console_tabs"`. That attribute names the **layout key** in `config.js`,
  not a zone — see `dom_adapter.js:175` and the comment at
  `incoming_live.ex:870`. Anyone applying a similar checklist to another page
  should read the layout key, not a zone name.

### ✅ Separate defect found from this stage's premise: `/reconcile` nav is dead — **FIXED 2026-08-06** (`2e4aa4d7`)

**It was three defects, not one.** The missing config was the one this
campaign found; reading the page to fix it turned up two more, and fixing
only the known one would have left the page just as dead:

1. **No `reconcile` entries in `config.js`** — as recorded below.
2. **`data-nav-default-zone="reconcile-list"` named a context, not the
   layout key.** Every other page names its layout key (`review`, `status`,
   `incoming`); `getZone()` hands that literal to `layouts[]`, so adding the
   config under a `reconcile` key would *still* have resolved to `{}`. Stage
   3 recorded this exact trap — "that attribute names the **layout key**" —
   and the defect was sitting in the page the stage was pointing at.
3. **The shared `ReviewTabs` strip was dead on `/review` too.** It declared
   `data-nav-zone="review-tabs"` with `data-nav-item` on both links, and
   nothing in the config answered that name — no selector, no instance type,
   no layout edge. So Identity ↔ Episode mapping was mouse-only on *both*
   review surfaces, which nobody had noticed because the rest of `/review`
   works. It is a zone tab strip already using the `zone-tab` classes, so it
   now names the existing `zone-tabs` zone and inherits `ZONE_TABS` rather
   than inventing a context.

**The test is deliberately not `reconcile_behavior.test.js`.** The stage
already worked out why that would prove nothing, and it was right. The check
that catches this class of defect is the config-integrity one the stage
specified: `assets/js/input/__tests__/config_coverage.test.js` reads the
templates and asserts the config answers what they declare — every
`data-nav-default-zone` names a real layout and has a cursor start, every
`data-page-behavior` resolves, every `data-nav-zone` has a selector. It
fails on all three defects before the fix.

It derives its expectations instead of listing them, because a hand-written
list is exactly what let this through: `index.test.js`'s "has layouts for
all zones" named five of the twelve. The next page that forgets its config
fails without anyone remembering to add it.

**Verified in a real browser, per the warning below.** Two awaiting files
seeded, then arrow keys driven through `chromium-probe`: list → detail → tab
strip → sidebar and back all move focus, and `/review` → up → right → Enter
lands on `/reconcile` by keyboard alone. Seeded rows removed afterwards.

---

*Original finding, kept for the record:*

Not part of the declined decision — the console's exclusion is deliberate,
`/reconcile`'s is not. `/reconcile` *looks* fully wired and is not:

| Declared in `reconcile_live.ex` | Present in `config.js` |
|---|---|
| `data-page-behavior="reconcile"` (+ registered behavior) | ✅ |
| `data-nav-default-zone="reconcile-list"` | ❌ no layout under that key |
| `data-nav-zone="reconcile-list"` / `"reconcile-detail"` | ❌ no `contextSelectors` entries |
| `data-nav-item tabindex="0"` on every row | ❌ no `instanceTypes` entries |
| — | ❌ no `cursorStartPriority` entry |

`buildNavGraph("reconcile-list", …)` returns `{}` and `resolveCursorStart`
returns `null`, so arrow keys do nothing. The page is structurally identical
to `review`, whose layout is three lines — the fix is a mechanical config
block, not a design question.

This also corrects the stage's own evidence table. "Page behaviors missing a
test: 1 (`reconcile`)" implied reconcile was otherwise healthy, and
checklist item 6 proposed a `reconcile_behavior.test.js`. That test would
assert `{onAttach, onDetach}` on an object literal and prove nothing — the
gap is config, not coverage. **A behavior test is not evidence a page is
navigable.** The check that would have caught this is a config-integrity
one: every `data-nav-default-zone` in a template must name a real layout,
and every `data-nav-zone` a real selector. `index.test.js:100` already
asserts the neighbouring invariant (cursor-start contexts have selectors)
but cannot catch a page absent from the config entirely.

### Original stage text (for reference)

> ⚠️ **Superseded — kept only to show what the stage believed going in.**
> The premise is declined and the checklist's central assumption (that the
> page runs the input system) is false. Do not implement from here.

**Why.** `/console` is the only routed page with no input-system wiring.
Every other page declares `data-page-behavior`; its source tabs, filter
chips and action footer are unreachable without a mouse.

**Evidence — re-verified 2026-08-06, after Stage 4.**

| Fact | Command | Value |
|---|---|---|
| nav attributes in `console_page_live.ex` | `grep -c 'data-page-behavior\|data-nav-zone\|data-nav-item'` | **0** |
| routed live pages | `grep -cE '^\s+live "' router.ex` | 12 routes / 11 pages (`/guide` has 2) |
| page behaviors | `ls assets/js/input/*_behavior.js` | 10 + the `page_behavior.js` registry |
| behavior tests | `ls assets/js/input/__tests__/*_behavior.test.js` | 9 |

`/console` is the **only** page without a behavior. `reconcile` is the
only behavior without a test — the earlier "11 / 9" reading counted the
registry as a page and implied two gaps where there is one of each.

**Owner decisions (2026-08-06).**

* **Zones are declared by the page; the drawer is left alone.** It keeps
  its mouse plus `` ` ``-shortcut model.
* **The log stream is scroll-only.** Not a zone.

### The stage's stated trap does not apply — here is why

The stage warned that `source_tabs` / `chip_row` / `action_footer` are
shared between `/console` and the global drawer, so adding nav attributes
to them would inject console zones into every page's DOM. **That is true
of `data-nav-zone` and false of `data-nav-item`**, because of how items
resolve.

`assets/js/input/core/dom_adapter.js` resolves a context's items with a
CSS selector from `config.js`, and every existing selector is the pair
`[data-nav-zone='X'] [data-nav-item]` — the item attribute only counts
*inside* a matching zone ancestor. So:

* `data-nav-zone` wrappers go in `console_page_live.ex` **only**. The
  drawer never renders them.
* `data-nav-item` may go on the buttons inside the shared components. In
  the drawer those items have no matching zone ancestor, so they match
  no selector and stay inert.

No `nav?` attr is needed, and no structural selector like
`.console-fullpage .console-chips button` — which would have worked, but
diverges from the house convention every other page follows.

**Implementation checklist.**

1. `lib/media_centaur_web/live/console_page_live.ex` (50 lines) — add
   `data-page-behavior="console"` and `data-nav-default-zone="console_tabs"`
   to the root `<div class="console-fullpage">`, and wrap each component
   call in a `<div data-nav-zone="…">`. Follow
   `watch_history_live.ex:159` for the exact shape.
2. `lib/media_centaur_web/components/console_components.ex` — add
   `data-nav-item` to the tab buttons (`source_tabs`), the chip buttons
   and level filter (`chip_row`, `.console-chips` / `.console-level-filter`),
   and the footer actions (`action_footer`). Inert in the drawer, per above.
   **Storybook stories must be updated in the same change** (MC0009).
3. `assets/js/input/config.js` — add a `console` entry under `layouts:`
   (line ~73) plus the three `contextSelectors`. Zones
   `console_tabs` → `console_filters` → `console_actions`, each
   `left: ["sidebar"]`, following the `settings` / `guide` layouts.
4. `assets/js/input/console_behavior.js` + register it in
   `page_behavior.js` (imports at lines 18–27).
5. `assets/js/input/__tests__/console_behavior.test.js` — mock DOM
   interface, assert behavior method return values, per the family.
6. Consider `reconcile_behavior.test.js` in the same change; it is the
   only other gap and the fixture work is shared.

**Verification.** `bun test assets/js/input/`; then drive the real page
with `chromium-probe` per `reference-input-nav-runtime-verification` —
wait for `phx-connected` on `[data-phx-main]` before issuing keys, and
assert on the state driving focus, not on animated properties. A green
`bun test` is not evidence the page is navigable.

## Stage 4 — Make the stated policies true again  ✅ **DONE 2026-08-06**

**Owner decisions.** Amend the policies to match practice **and enforce
each with a Credo check**; fix the naming-contract sites **and add a check**.
Both went further than "reword": every amended rule now has code behind it.

### The evidence was wrong in both directions

The stage was scoped from two counts. Both were misleading, and this file
had already recorded the lesson — *"a number with a command next to it
still needs the command run"* — twice.

| Recorded | Actual | Why |
|---|---|---|
| 301 `Repo.*` in `test/` | **450** | `Repo\.[a-z_]*(` can't match a `!`, so every `Repo.get!` / `update!` / `insert!` was invisible. Of the 450, **114 were writes**; the rest were reads. |
| 345 `=~` in live tests | **14** structural | Of 312 with a string-literal RHS, all but 14 assert **user-visible copy** — which the amended policy explicitly permits. The "violation" was ~95% phantom. |

The second correction reframed the stage: there was never a 345-site
markup problem. The real work was 14 sites (17 under the final rule) and
a policy that had been overclaiming for months.

### What landed

**Three Credo checks**, each red on a deliberately-wrong function first,
and each verified against the real codebase — not just its unit tests.
MC0022 was additionally proven live by reintroducing the exact
`fetch_for_extra/1` regression and watching `mix credo` flag it.

| ID | Rule | Grandfathered |
|---|---|---|
| **MC0022** `LookupNamingContract` | `fetch…` → tuple, `get…` → nil-able, `…!` raises | none |
| **MC0023** `NoRepoSetupInTests` | `Repo` **writes** are setup (banned); **reads** are assertions (allowed) | 23 files |
| **MC0024** `NoMarkupSubstringAssertion` | no `=~` on HTML *attributes*; use `has_element?/2` | none |

MC0022 and MC0024 only fire where they can be *sure*. MC0022 reads the
return shape (a tail call to `Repo.get`/`get_by`/`one`, `Map.get`,
`Enum.find`, or a `case` with both `{:ok, _}` and `{:error, _}` branches)
and stays silent otherwise, so `TMDB.Client.get_movie/2`,
`Console.Buffer.get_filter/1` and `Settings.get_by_key/1` are not
second-guessed. MC0024 matches attribute-*shaped* literals only, so
`<path>` redaction placeholders, `rid=7`, and `metadata-activity` don't
trip it. Neither needed a single grandfather entry — the alternative was
a check that cried wolf and got ignored.

**Five contract fixes, not the two the stage named.** MC0022 found three
the campaign never knew about:

| Was | Now | Sites |
|---|---|---|
| `ProgressRecords.fetch_for_extra/1` → `nil` | → `{:ok, _} \| {:error, :not_found}` | 3 lib, 5 test |
| `Review.get_pending_file/1` → tuple | `Review.fetch_pending_file/1` | 1 lib, 3 test |
| `Settings.get_by_key/1` → `{:ok, Entry \| nil}` | → `Entry \| nil` | ~32 sites |
| `Acquisition.Pursuits.get/1` → tuple | `…fetch/1` | 7 |
| `Pursuits.Units.get/1`, `Plans.get/1` → tuple | `…fetch/1` | 33 |

`Settings.get_by_key/1` was the interesting one. It returned `{:ok, _}`
in **every** branch — it could not fail — so the tuple carried no
information and every caller paid a `case` for it. It is now the honest
sibling of the `get_cached/1` that already sat directly beneath it.
Grandfathering it would have meant exempting the largest violator on the
check's first day.

**Factory affordances**, so forced setup has somewhere legitimate to go:

| Helper | For |
|---|---|
| `force_attrs(record, attrs)` | forcing fields on one record |
| `backdate(record, field, datetime)` | ageing a timestamp |
| `force_state(record, state)` | skipping a state machine |
| `force_where(queryable, set)` | the same, in bulk by query |

`force_where/2` was not planned. It appeared because MC0023 caught eight
`Repo.update_all` sites that the stage's own grep had missed (`update_all`
doesn't match `Repo\.update!?\(`) — the *third* instance of the counting
lesson in one stage. Adding the bulk sibling beat grandfathering six more
files. **40 setup sites converted** (32 changeset pipelines + 8 bulk).

**Policies reworded** in `coding-guidelines/SKILL.md` and
`automated-testing/SKILL.md`, each now naming the check that enforces it,
plus a new *Lookup Naming Contract* section pointing at MC0022.

### A `Database busy` scare, and what it actually was

Two full-suite runs failed with `(Exqlite.Error) Database busy` on
`INSERT INTO settings_entries`, from `DiagnosticsBadge.mark_seen/0` in
`StatusLive.mount` and `Capabilities.save_test_result/2` in a setup block.
Recorded because the false trail is instructive.

Bisecting cleared the stage's own changes: without the new test files
2/2 clean, with only the Credo tests 2/2 clean, with all four 3/3 clean,
and `main` 4/4 clean. The `Settings` reshape is read-path only. So the
first conclusion was "a writer held a lock for over ten seconds
(`busy_timeout` is 10 000 ms) — something is stuck." **That was wrong on
both counts.**

* `config/test.exs` already documents this failure mode, at the line that
  sets the timeout: *"occasionally raised `Exqlite.Error: Database busy`
  from `Settings.put_*` writes under load"* — with a pointer to
  `flaky-tests.md (#1)`. It is a **known load-contention mode**, already
  mitigated once by raising the timeout from 2 000 ms. Not novel, and not
  a stuck writer.
* Both failures land inside the window of two commits made on `main`
  during the session (`b4de2c65` 15:02, `89523da4` 15:09) — i.e. someone
  else was working, almost certainly running the suite. All eight runs
  outside that window are clean. **Two `mix test` runs against the same
  SQLite file** is exactly what produces a cross-connection write-lock
  timeout.

Nothing to fix here, and nothing for the next session to chase — but the
timeout has now been *observed* to be insufficient under a concurrent
suite, which is worth knowing before anyone raises it a second time.

**Method note.** The bisect was worth doing and the diagnosis was not.
Four full-suite runs proved the change was innocent; the "stuck writer"
theory came from reading `busy_timeout` and reasoning, when the same file
three lines up already said what this was. Read the comment next to the
constant before theorising about it.

### Original stage text (for reference)

> ⚠️ **Superseded — kept only to show what the stage believed going in.**
> Every number below is wrong or misleading; the corrections are in
> *"The evidence was wrong in both directions"* above. Do not quote from
> here.

**Why.** Two written policies now describe a codebase that does not
exist. That erodes the credibility of the policies that *are* followed
— and this repo's are unusually well followed.

**Evidence.**

| Policy | Location | Reality |
|---|---|---|
| "never call `Repo` directly from tests" | `.claude/skills/coding-guidelines/SKILL.md` | **301** `Repo.*` calls in `test/` |
| "no `=~` on markup" | `.claude/skills/automated-testing/SKILL.md` | **345** `=~` assertions across `*_live_test.exs` |
| naming: `fetch_*` tuple / `get_*!` raise | de-facto, `Library` | `Review.get_pending_file/1` returns a tuple; `ReleaseTracking.get_item/1` and `WatchHistory.get_event/1` return `nil` |

The first two counts were re-measured 2026-08-06 and differ from the
figures originally recorded (457 / 410). Stage 1 changed neither — its
commits touched **zero** `Repo.` lines in `test/` — so the original
numbers were produced by a different (unrecorded) match. Commands, so
the next reading is comparable:

    grep -rho 'Repo\.[a-z_]*(' test/ | wc -l
    grep -rho '=~' test/**/*_live_test.exs | wc -l

Most `Repo` uses in tests are legitimate — asserting a row landed, or
forcing a state the public API deliberately won't produce (20 sites use
`Ecto.Changeset.change(...) |> Repo.update!()` to backdate or force a
pursuit state).

**Approach.**
* Reword to what is actually intended: no `Repo` for *setup*; `Repo`
  for *assertion* is fine. Scope the markup rule to *structural* markup
  (class names, tag nesting), not user-visible copy.
* Add the missing factory affordances so the setup cases have somewhere
  legitimate to go: `TestFactory.backdate(record, field, datetime)` and
  `TestFactory.force_state(pursuit, state)` in `test/support/factory.ex`.
* Unify the lookup contract: `fetch_*` → `{:ok, _} | {:error,
  :not_found}`, `get_*!` → raises, nothing else. Rename
  `Review.get_pending_file/1`, `ReleaseTracking.get_item/1`,
  `WatchHistory.get_event/1`, and the two former `Library` stragglers —
  see below for where they went.

**Stage 1 moved these targets, and made one of them worse.** The two
`Library` stragglers this stage named no longer exist under those names:

| Was | Now | Contract |
|---|---|---|
| `Library.get_extra_progress_by_extra/1` | `Library.ProgressRecords.fetch_for_extra/1` | returns `nil` — **violates** the `fetch_*` contract |
| `Library.get_media_track_override/2` | `Library.MediaTrackOverrides.get/2` | returns `nil` — consistent with `get_item` / `get_event` |

`fetch_for_extra/1` is a regression against the contract this stage
proposes: it was honestly named `get_*` returning `nil`, and the
extraction renamed it to `fetch_*` while leaving the return shape alone.
Stage 1 was not applying this stage's contract (they were deliberately
kept separate), so nothing was checking. Fix it here — either restore
`get_` or make it return the tuple — and prefer the tuple, since every
other `fetch_*` in the extracted modules (`Containers.fetch/2`,
`Seasons.fetch/1`, `Episodes.fetch/1`, `PlayableItems.fetch/1`,
`Extras.fetch/1`, `ProgressRecords.fetch_for_container/2`) already
returns one. That makes `fetch_for_extra/1` the single odd one out
rather than the start of a second convention.

This is also evidence for the second open question below: an
arity+prefix Credo check would have caught the rename at the moment it
happened.

**Open questions — both answered 2026-08-06.** Amend *and* enforce; fix
the sites *and* add a check. The stage's own guess that a naming check
could only manage "arity+prefix heuristics" turned out to be too
pessimistic — reading the return shape off the AST is both feasible and
what makes the check safe enough to ship with zero exemptions.

**Verification.** `mix precommit` green — credo clean (109 checks), 5710
Elixir tests, 557 JS tests, zero warnings. Each check went red on a
deliberately-wrong function before it went green.

---

## Stage 5 — Pick one event-publication idiom  ✅ **DONE 2026-08-06**

**Outcome.** Both open questions answered by the owner; ADR-060 written
first, then the transport, then `Review` as the worked example.

1. *Typed structs — target or roll back?* → **Target**, in the
   `Library`/`Playback` shape. Not the `Pursuits` shape, which is
   persistence ceremony and does not spread.
2. *Does the `Topics` pair land independently?* → **Yes**, and it landed
   whole rather than on-next-touch, because it is mechanical.

**What shipped.**

* **ADR-060** — one `events.ex` per topic with a closed message set;
  nested structs with `@enforce_keys`; one `broadcast/1`. Migration is
  per-context **on next touch, never a sweep** — the originating audit's
  headline finding was that this repo's defects come from refactors that
  stop at 80%, and a single pass over 52 modules is that defect.
* **`Topics.publish/2` / `subscribe/1` / `unsubscribe/1`** — 132 call
  sites across 71 files converted. Topic names stay zero-arity functions,
  not atoms: a misspelt `Topics.review_updates()` fails to compile.
* **`Review.Events`** — the worked example. `FileAdded`, `FileReviewed`,
  `GroupApproved`, `GroupError`; subscribers (`ReviewLive`,
  `ShellBadges`, `Status.Views.Overview`) converted in the same commit.
* **Three Credo checks**: MC0025 (transport), MC0026 (`review:updates`
  chokepoint), and a **repair of MC0012/MC0013**, which had never been
  able to fire — see *Decisions made*.

**Numbers after, each with its command.**

| Fact | Command | Before | After |
|---|---|---|---|
| `MediaCentaur.PubSub` literals in `lib/` | `grep -rho 'MediaCentaur\.PubSub' lib/ --include='*.ex' \| wc -l` | 134 | **4** |
| …of which are call sites | `grep -rn 'Phoenix\.PubSub\.\(broadcast\|subscribe\|unsubscribe\)(' lib/ --include='*.ex' \| grep -v topics.ex \| wc -l` | 136 | **0** |
| `Topics` defs (36 topic names + 3 transport) | `grep -c '^  def ' lib/media_centaur/topics.ex` | 36 | **39** |
| Credo checks registered | `mix credo --strict` header | 109 | **111** |
| Contexts with an `Events` chokepoint | `find lib -name 'events.ex'` | 4 | **5** |

**The stage's own verification criterion was wrong, and was corrected
before it was written down.** It said the literal grep "should read 0".
It cannot: `application.ex` must name `MediaCentaur.PubSub` to start the
server. The honest check is MC0025, which matches *call sites* and so
ignores the child spec entirely. The four survivors are the seam's own
`@pubsub`, the child spec, and two moduledoc mentions. This would have
been the campaign's sixth recorded-then-disproved number; it was caught
by running the command while writing the criterion.

**Suite verified against the known flake family.** The first full run
failed one test (`Library.Views.DetailTest`, an ETS teardown race); the
next failed a *different* one (`Downloads.QueueMonitorTest`); the seed
that produced the second then passed twice. Five clean full runs on this
tree, plus `mix precommit` green end-to-end. Both failures are the
pre-existing concurrency-flake family, not this change — the campaign's
rule is to confirm on `main` before blaming your own work, and the
varying identity of the failing test is the signature.

## Stage 6 — Opportunistic polish  ✅ **DONE 2026-08-06**

Small, independent, each safely done in a spare slot. **Not gating
anything** — an item that turns out bigger than its bullet gets dropped with
a note, not grown. One item took that exit; the note is below and it is the
useful part of this stage.

**All six re-verified 2026-08-06, after Stage 5**, then resolved the same
day. Every figure carries the command that produced it.

| # | Item | Outcome |
|---|---|---|
| 1 | Boolean-setting boilerplate | ✅ `MediaCentaur.BooleanSetting`; 175 → 60 lines across the four modules (`3ceac88f`) |
| 2 | Cast grid renders all, hides past 24 | ✅ server-side selection; **1.6 MB → 41 KB** of HTML (`81a26c64`) |
| 3 | `clear_database` native confirm | ⛔ **DROPPED** — 5 sites, 2 competing idioms, an owner decision |
| 4 | `home_feed` raw-SQL fragments | ✅ three Ecto builders replace four fragments (`d4178d76`) |
| 5 | Preload volume | ✅ aggregates instead of `seasons: [:episodes]` (`d4178d76`) |
| 6 | `Topics.publish/2` / `subscribe/1` | ~~pending~~ → **SHIPPED in Stage 5** (`5328226f`) |

Plus the unclaimed `/reconcile` defect, fixed in `2e4aa4d7` — see its own
section, because it was three defects rather than one.

**What each item cost, measured rather than estimated:**

| Item | Claim | What it actually was |
|---|---|---|
| 1 | "285 lines for 4 flags" | Count right, remedy covered 175. Repo is 36 lines lighter, not 115 — the win is 4 copies of one decision becoming 1 |
| 2 | "a 900-member series emits 900 cards" | Understated. 899 cards = **1 665 644 bytes** of HTML to show 24 |
| 4 | "re-expresses the join the `exists` already states" | Exactly right, all four sites |
| 5 | "loading every episode to compute two integers" | Exactly right |

---

* **Boolean-setting boilerplate** —
  `lib/media_centaur/{spoiler_free,library_backdrop,library_card_info,incoming_backdrop}.ex`
  plus their four `*_aware.ex` traits: **8 modules, 285 lines, for 4 flags**
  (count verified). `library_backdrop.ex` and `incoming_backdrop.ex` are
  identical apart from the key, the module name, and two doc sentences.

  ⚠️ **The bullet overstates the opportunity, and its remedy only covers
  half.** `MediaCentaurWeb.Live.SettingAware` **already is** the shared
  abstraction for the web side: subscribe-once-per-host, seed the assign,
  attach the `:handle_info` hook. The four `*_aware.ex` files (110 lines
  total, 20–36 each) are thin registrations of it, and they **cannot fully
  collapse** — each passes a unique *literal* atom hook name, deliberately,
  so no atom is created at runtime.

  The genuine duplication is the **four context modules, 175 lines**, which
  differ only in key and polarity. A `use MediaCentaur.BooleanSetting,
  key: "…", default: false` macro generating `setting_key/0`, `enabled?/0`
  and `enabled?/1` collapses those to a `use` line each.

  ⚠️ **Polarity is not uniform** — `library_card_info` is default-**on**
  (`enabled?(%{"enabled" => false}), do: false` / `enabled?(_), do: true`);
  the other three are default-off. The macro must take `default:` and
  generate both polarities, or it will silently flip a user's setting.
  Realistic saving: ~175 lines → one macro plus four `use` lines. The traits
  stay.

  ✅ **Done** (`3ceac88f`). The polarity warning was the useful part, and it
  turned out to need no branching at all: both polarities collapse into
  `enabled?(%{"enabled" => enabled}) when is_boolean(enabled)` falling back
  to `default:`. Where the macro *does* pay for the warning is refusing to
  compile on a non-boolean `default:` — the failure mode is silent
  inversion of a user's setting, so it fails the build instead, and that
  guard is tested against an actual bad default.

  Honest numbers: the four modules go 175 → 60 lines and the generator is
  79 (mostly moduledoc), so the repo is **36 lines lighter, not 115**. The
  line count was never the point; four copies of one decision became one.
  `SpoilerFree` was the only one of the four with no unit test pinning its
  polarity, so it has one now.

* ✅ **Cast grid** — the stage's most valuable change, and it read like its
  least. Rendered *every* cast member, hiding all past `@max_cast_cards 24`
  with `display: none`, so a JS hook could filter without a round-trip.
  **Measured: 1 665 644 bytes of HTML for one 899-member series, to display
  24 cards.** Now 41 KB.

  **Both proposed remedies were wrong**, which is why measuring first
  mattered. *Capping the rendered window* breaks the filter's only purpose —
  you filter to find someone billed 300th, and a capped window answers "no
  matches", which is worse than a slow grid. *Passing the list as a `data-`
  attribute* puts a second copy of the card markup in JavaScript.

  The fix was to stop treating it as a rendering problem. Selecting cast for
  a query is a *data* question and the data is on the server, so the filter
  became a `phx-change` and `CastGrid.visible_cast/3` became the whole rule —
  pure, public, unit-tested, where the old rule was a DOM-driven hook. The
  hook and its tests are deleted: 271 lines out, 161 in. Filter state lives
  in `EntityModal` with the rest of the modal's state and resets on entity
  switch.

  The no-flash constraint dissolved rather than being satisfied: nothing
  beyond the 24 is ever rendered, so there is no full grid to flash. The
  "no round-trip" justification in the old moduledoc did not survive
  contact with the fact that this is a desktop app talking to localhost.

  Verified in a browser, not just green: typing `tina` against the 899-member
  cast returns Tina Fey **and** Christina Gausas — the second billed far past
  the 24-card window, which is exactly the case a capped window would have
  broken silently.

* ⛔ **`clear_database` confirmation — DROPPED**, and this is the item worth
  reading. The bullet is right that a native `data-confirm` on the app's most
  destructive action ignores the theme and is not d-pad reachable. Its
  remedy is not a small change, for two reasons the count kept hiding.

  **It is five sites, not one or two** (`grep -rn data-confirm
  lib/media_centaur_web/`): `settings_live/danger.ex:214` (clear database)
  and `:235` (refresh image cache), `console_components.ex:255` (clear log
  buffer), `settings_live/library.ex:197` (remove excluded dir),
  `watch_history_live.ex:314` (remove from history). Converting the two in
  `danger.ex` and leaving three elsewhere is the same 80 % stop the stage
  warned about, one level up.

  **And "use ModalShell" is not the obvious answer**, because the repo
  already has two confirmation idioms and neither is ModalShell:
  `MediaCentaurWeb.Components.Modal` is the single modal seam (MC0017 —
  nothing else may use `modal-backdrop`/`modal-panel`), and the detail
  panel's delete flow uses an **inline two-click gesture**
  (`delete_confirm` + `delete_gesture_state/3`) that is already themed and
  already d-pad reachable. Picking between them across five sites — and
  deciding whether "delete everything" deserves something stronger than one
  more click — is a design decision, which the working agreement puts with
  the owner, not with the agent.

  So it does not belong in a stage described as *no discussion needed*. It
  wants its own: one shared confirm component, one idiom, all five sites,
  and a Credo check making `data-confirm` the violation — the shape Stage 4
  used to make a policy true instead of merely stated.

  → **That stage now exists: Stage 8**, with the five sites tabulated and
  the idiom choice written up as open questions.

* **`home_feed.ex` raw-SQL fragments** — the `fetch_in_progress_*` functions
  each embed a raw-SQL `fragment` (lines **246, 343, 439, 537**) that
  re-expresses in string SQL the join the Ecto `exists` clause already
  states, naming five tables as literals that a rename would break silently.
  The *correctness* bug here is fixed (commit `914e94c9`); the duplication
  is not. A shared `latest_watched_at_subquery(container_type)` built with
  Ecto replaces them. Untouched by Stage 1 — `HomeFeed` was already
  extracted. The fragment at :189 is an unrelated `TRIM` — leave it.

  This is the largest genuine cleanup left in the stage.

  ✅ **Done** (`d4178d76`). The four fragments answer one question in two
  shapes — containers whose playable items point straight at them, and
  containers watched through children — so three Ecto builders cover all
  four sites. The joins are inner, which is safe *because* every fetcher
  already requires a progress row via its first `exists`; that was checked
  per fetcher, not assumed. `max/1` also replaced two `LIMIT 1`s that took
  an arbitrary progress row from titles with more than one playable item.
  The string table names in the surrounding `exists` clauses went with them.

  **The test needed for this was not the obvious one.** Final row order is
  decided in Elixir (`Enum.sort_by` in `list_in_progress/1`), so a
  sortedness test passes with the `order_by` deleted entirely. What these
  fragments actually decide is *which rows survive each per-type `limit`*.
  Four tests, one per container shape, seed more in-progress titles than the
  limit and assert the most recently watched survive — and inverting the
  four `order_by` directions was run first, failing all four, before the
  rewrite touched anything.

* **Preload volume in `fetch_in_progress_tv_series/1`** —
  `home_feed.ex:358` does `Repo.preload([:images, seasons: [:episodes]])`,
  loading every episode of every returned series to compute two integers.
  Now that the completeness test is in SQL, those can be `COUNT` aggregates.

  `Library.ProgressRecords.summaries/1` (extracted in Stage 1) already
  computes exactly these totals as SQL `COUNT` aggregates, in
  `episode_totals_by_tv_series/1` (`progress_records.ex:433`). Check whether
  that is directly reusable **before** writing a third version — pairs
  naturally with the `home_feed` item above.

  ✅ **Done** (`d4178d76`), and the instruction to check first was worth
  following: `episode_totals_by_tv_series/1` was **private**, so neither
  reusing nor copying it was available. Counting a series' episodes is an
  `Episodes` concern rather than a progress one, so it moved to
  `Episodes.count_by_tv_series/1` and `ProgressRecords` now calls that —
  one implementation instead of the two a third version would have made.
  The preload is gone; both numbers are aggregates now, asked for as
  aggregates.

* ~~**`Topics.publish/2` / `Topics.subscribe/1`**~~ — **done.** Landed whole
  in Stage 5 rather than early-and-partial: 132 call sites across 71 files,
  held by MC0025. Nothing to pick up.

## Stage 7 — The JS tests nobody runs  ✅ **DONE 2026-08-06**

**No open questions.** Nothing here needed the owner: the tests were supposed
to run, they did not, and the ones that existed were failing. This is the
campaign's own headline lesson found in the tooling that was verifying the
campaign.

**Why it mattered more than its size.** Every "green" claim in Stages 1–6 was
made against a suite that silently skipped a directory. That does not
invalidate them — nothing in those stages touched `assets/js/hooks/` — but
it does mean the guarantee was narrower than it read.

### What landed

| Change | Where |
|---|---|
| `mix test.all` runs the whole JS tree | `mix.exs` — `assets/js/input/ assets/js/__tests__/` → `assets/js/` |
| CI runs what precommit runs | `.github/workflows/ci.yml` |
| Browser globals installed per test, unconditionally | new `assets/js/test_support/dom_stubs.js` |
| `console.test.js` and `log_tail.test.js` own their `window` | both now call the installers from `beforeEach` |
| The Console→LogTail repin contract has a sender-side test | `console.test.js` — 3 new tests |

**564 tests across 24 files → 620 across 29, 0 failures.** That count going up
is the observable proof the widening took effect; a green run alone would have
proved nothing, which is the whole point of the stage.

Both runners were widened to `assets/js/` rather than gaining
`assets/js/hooks/` as a third path. Enumerating directories is what created
the gap, so a new directory is now covered by default rather than by someone
remembering. Verified nothing outside `assets/js/` is picked up: 29 collected
files is exactly `find assets/js -name '*.test.js'`.

### The diagnosis below was half wrong — read this first

This stage was written from a stack trace, and the trace was not the cause.

Eight identical `TypeError: window.dispatchEvent is not a function` at
`console.js:66` reads unambiguously as "the stub lacks `dispatchEvent`". Run
the file by itself and it is **17 pass, 0 fail** — no `TypeError` at all,
because there `window` *is* `globalThis`, and bun's `globalThis` has a real
`dispatchEvent`. The failures need `log_tail.test.js` to load first:

```
bun test assets/js/hooks/console.test.js                       # 17 pass  0 fail
bun test assets/js/hooks/log_tail.test.js .../console.test.js  # 21 pass  8 fail
```

The actual cause is that neither file owns its globals. Both install stubs
with the guarded idiom —

```js
if (typeof window === "undefined") { globalThis.window = ... }
```

— which by construction means *the second file to load silently runs against
the first file's stub*. `log_tail`'s `window` has only `addEventListener` and
`removeEventListener`, so `console.js`'s repin dispatch throws.

It cuts the other way too, and that half is worse. Alone, `console.test.js`
overrides `window.addEventListener` while leaving bun's native
`dispatchEvent` in place — two registries that never meet. So the repin
dispatch went nowhere, silently, and 17 tests reported success. **The same
idiom produced a false red and a false green in the same file**, and only the
red was visible.

So the fix is not "add the missing method". It is `test_support/dom_stubs.js`:
installers that assign unconditionally, from `beforeEach`, with one listener
registry behind `addEventListener` / `removeEventListener` / `dispatchEvent`.
No test can now inherit another file's globals or observe another test's
listeners. The module's header comment carries this reasoning, because the
guarded idiom is the one a future contributor will reach for by default.

Stage 6's rule — record the finding, don't grow the stage — applies to what
this turned up in `log_tail.test.js`: its repin test hand-swapped
`globalThis.window` to capture the handler and called it directly. It now
dispatches the event the way `console.js` does. That is a stronger assertion
over the same behaviour, not a rewrite of it.

### Original evidence (verified 2026-08-06, corrected above)

| Fact | Command | Value |
|---|---|---|
| What `mix precommit` ran | `mix.exs`, pre-stage | `bun test --dots assets/js/input/ assets/js/__tests__/` |
| What CI ran | `.github/workflows/ci.yml`, pre-stage | `bun test --dots assets/js/input/` |
| Tests in `assets/js/hooks/` | `bun test assets/js/hooks/` | 53 tests, 5 files — **8 failing** |
| Distinct root causes | `bun test assets/js/hooks/ \| grep -E '^TypeError' \| sort -u` | **1** |
| Failing since | `git log -1 -S 'mc:log-tail:repin' -- assets/js/hooks/console.js` | `358bab78`, **2026-04-29** |

**Two gaps, not one.** `assets/js/hooks/` (5 test files) is run by *neither*
precommit nor CI. `assets/js/__tests__/` (1 file,
`reconnect_on_visible.test.js`) is run by precommit but **not** by CI — so a
green local run and a green CI run do not mean the same thing.

**The count shrank the stage rather than growing it.** "8 failing tests"
sounds like eight problems; it is one. All eight throw the same
`TypeError: window.dispatchEvent is not a function` — `console.js:66`
dispatches `mc:log-tail:repin` on the drawer's closed→open transition. ~~and
the test's `window` stub in `console.test.js` never gained a `dispatchEvent`.
The hook gained the dispatch on 2026-04-29 and the stub did not follow.~~
**Wrong — see the correction above.** The stub was not the variable; the file
inherits `log_tail.test.js`'s `window`, and alone it passes 17/17. The
tests have been red for three months and no run has ever reported it.

This is error 6 one level up. MC0012/MC0013 reported success because they
could not fire; this reports success because it is never invoked. **An
unexercised check is not a weaker guarantee than no check — it is a false
one.**

### Shape of the fix — as planned, all three done

1. ✅ Widen both runners to the whole tree — `bun test assets/js/` — rather
   than adding `assets/js/hooks/` as a third path. Enumerating directories
   is what created this gap; a new directory should be covered by default,
   not by remembering. Confirm nothing outside `assets/js/` is picked up.
2. ✅ Fix the stale `window` stub so the 8 pass. Check whether the dispatch is
   *worth* asserting while there — a test that only stops throwing is
   weaker than one that pins the repin behaviour `358bab78` added.
   **Both halves paid off**: step 2 is where the diagnosis turned out to be
   wrong, and the repin question turned into the 3 tests that now pin the
   sender side of the contract.
3. ✅ Re-run and read the count: 53 tests must all pass, and the totals
   reported by `mix precommit` must **go up**, which is the observable proof
   the widening took effect. 564/24 → 620/29.

Do not stop at making the suite green — the point is that it now runs.

## Stage 8 — One confirmation idiom  ✅ **DONE 2026-08-06**

Carried out of Stage 6, which dropped it correctly: it is not polish. See
that stage's `clear_database` bullet for the full reasoning; this is the
work it implies.

### The owner's answers, and the rule they produced

The three open questions went to the owner. The first answer was **none of
the options offered** — and it is the one that made the stage right:

> *remove excluded dir and history row require no confirmation.*

Both had been framed as "which dialog?" when the correct treatment was **no
dialog**. Two of the four in-scope sites simply lost their confirmation.
"Clear database" got *"probably whatever is our largest confirmation"* — the
persistent modal, this repo having no typed-confirm or hold-to-confirm to be
larger. The console was ruled out of scope.

The rule that fell out, now enforced by **MC0027**:

| Consequence | Treatment | Sites |
|---|---|---|
| Trivially reversible | **Nothing** | Remove excluded directory · Remove watch-history row |
| Costly but recoverable | **Arm in place** (Confirm / Cancel) | Refresh image cache |
| Irreversible **and** unbounded | **Persistent `<.modal>`** | Clear database |

Grading by consequence rather than by surface is what stopped this becoming
five ad-hoc choices. Note the shape of the correction: every option on the
table was a *kind of dialog*, because the question was "which idiom", and
that framing quietly assumed each site deserved one. Two did not.

### What landed

| Change | Where |
|---|---|
| Clear database raises a persistent modal; `clear_database` is reachable only from inside it | `settings_live.ex` — new `clear_database_modal/1`, `clear_database_prompt` / `cancel_clear_database` |
| Refresh image cache arms to Confirm / Cancel | `settings_live/danger.ex` |
| Excluded directory + watch-history row delete outright | `settings_live/library.ex`, `watch_history_live.ex` |
| `data-confirm` is now a Credo violation | `credo_checks/native_confirm_dialog.ex` (MC0027) + test |
| Wiki caught up | `Settings-Reference.md`, `Watch-History.md` |

**The in-place idiom came from the page, not from the detail panel.** Settings
already arms the media-directory rows into an explicit **Confirm** / **Cancel**
pair; the detail panel flips a single button's label to "Click again to
confirm". Both are fine, but Refresh sits three rows from the media-directory
list, so it copies its neighbour. An earlier draft used the label-flip and was
replaced on reading the page — that would have put two arm-in-place shapes on
one screen, which is the exact drift the stage exists to remove.

**MC0027 exempts the console** (`@exempt_files`), the owner's answer to
question 3, with the reason written where the exemption lives rather than in
a campaign nobody will read again.

**Verified in a real browser** (`chromium-probe` against the dev server, per
the green-`render_click`-is-not-a-click rule): the modal opens on prompt,
**Escape and backdrop clicks do not dismiss it**, Cancel closes it, Refresh
arms and disarms, and the only `data-confirm` left anywhere is the console's.

### The bug this stage caused, and what it says about waiting

Adding the modal broke two `settings_live_media_dirs_test.exs` tests that
touch nothing it changed. They wait for a debounced validation with

```elixir
render_until(view, "video files")
```

and the modal's copy says "Your **video files** remain untouched". The modal
is always in the DOM, so the wait was satisfied instantly, the form submitted
before the debounce landed, and the save persisted an empty directory.

**A wait predicate that unrelated copy can satisfy is a false green with a
delay fuse.** It does not fail when it stops working — it stops waiting, and
something downstream fails later, somewhere else. The preview now carries
`id="media-dir-preview"` and both tests wait on the element. That is MC0024's
principle (parse the document, don't substring the markup) applied to waiting
rather than asserting.

### Original evidence (verified 2026-08-06)

Five native browser `data-confirm` dialogs
(`grep -rn 'data-confirm' lib/media_centaur_web/`):

| Site | Action |
|---|---|
| `live/settings_live/danger.ex:214` | Clear database — the most destructive action in the app |
| `live/settings_live/danger.ex:235` | Refresh image cache |
| `components/console_components.ex:255` | Clear log buffer |
| `live/settings_live/library.ex:197` | Remove excluded directory |
| `live/watch_history_live.ex:314` | Remove from watch history |

The native dialog ignores the theme and is not d-pad reachable, which is the
real defect: this app is driven by a gamepad from a couch.

**The repo already has two themed, d-pad-reachable idioms**, which is why
"convert it to a modal" is a decision rather than an edit:

* `MediaCentaurWeb.Components.Modal` — the single modal seam. MC0017 forbids
  any other module using `modal-backdrop` / `modal-panel`. Takes a required
  `dismiss:` of `:ephemeral` | `:persistent`.
* The detail panel's **inline two-click gesture** — `delete_confirm` +
  `delete_gesture_state/3`. The button itself flips to a confirm state. No
  overlay, already themed, already navigable.

### Open questions — answered 2026-08-06, kept for the shape of the answers

1. **Which idiom?** The inline gesture is lighter and proven, but has
   nowhere to put a full warning sentence. A modal reads as more serious and
   fits the copy, at the cost of an overlay for "remove this row from watch
   history". A plausible answer is *both* — gesture for the small reversible
   ones, modal for the destructive ones — but that is a rule someone has to
   state, or it becomes five ad-hoc choices again.
2. **Does "Clear database" deserve more than one more click?** It deletes
   every entity, file, image and progress record. Options: nothing extra, a
   typed confirmation, or a hold-to-confirm.
3. **Is the console's "clear log buffer" even in scope?** Per the
   `feedback-console-outside-input-system` rule the console is deliberately
   outside the input system. It is *not* obviously outside a shared
   confirm-dialog convention, but it is worth one sentence rather than an
   assumption — Stage 3 was lost to exactly this kind of unchecked premise.

### Shape of the fix, as planned — and where it was wrong

> One shared component, one idiom rule, **all five sites in the same change**,
> and a Credo check making a bare `data-confirm` in `lib/media_centaur_web/`
> the violation. That last part is what Stage 4 established: a policy that is
> merely written down drifts, and a policy with a check does not. Converting
> two sites and leaving three is precisely the 80 % stop this campaign has
> been retiring.

The rule and the check were right; **"one shared component" was not.** Once
two sites dropped their confirmation and one took the existing media-directory
Confirm/Cancel shape, the modal had exactly one caller — and a shared
component with one caller is speculative abstraction, not sharing. What is
shared is the *rule*, and MC0027 is where it lives.

"All five sites in the same change" survived, in the form the answers left it:
four converted, the fifth exempted on the record.

## Stage 9 — The cache the sandbox can't reach  ✅ **DONE 2026-08-06**

The heading used to say *GenServer*. That was the error this stage cost, and
it is left visible in the title rather than quietly edited out.

### Two corrections before anything else

**1. The documented repro does not reproduce.** Run exactly as written —
five inert tests at `test/media_centaur/zz_ordering_probe_test.exs`, then
`mix test --seed 508425 --max-cases 24` — on the same tree it was measured
on (nothing but docs commits since): **5785 tests, 0 failures**, 124
seconds. A seed lottery is a function of the *module list*, so it expires
the moment the list changes — including when the five inert tests that
created it are named differently. It was true when written and useless a
day later.

**2. The named cause was one layer off.** `QueueMonitor` is **not started
under `:test`** — `Application.pubsub_listeners(:test)` returns `[]`, one
line away from the sentence claiming its state survives every test
boundary. No GenServer state survives anything here; the process dies with
`start_supervised!`. What survives is the `:persistent_term` key
`{QueueMonitor, :state}`, written by `store_and_broadcast/1` when
`queue_monitor_test.exs`'s *multi-client polling* block starts **its own**
monitor against stubbed clients: one torrent item, one usenet item, one
completed usenet history item — the measured `queue_monitor_items=3`,
exactly.

The number was right. The label on it was never checked, and the label is
what the fix options were written against: **option 3 as tabled ("reset
registered stateful processes") would have fixed nothing**, because there
is no process to reset.

### A deterministic repro, in 1.2 seconds

Two files, no seed lottery, no padding:

```bash
mix test test/media_centaur/downloads/queue_monitor_test.exs \
         test/media_centaur_web/live/incoming_live_test.exs:1701 --seed 0
```

Red before the fix, with the reported assertion and message. The `:1701`
matters: run whole, `incoming_live_test.exs` cleans the cache in an earlier
test and hides its own bug.

### What landed

`test/support/global_state_sandbox.ex` — `MediaCentaur.GlobalStateSandbox`,
called from `DataCase.setup_sandbox/1` (so `ConnCase` too):

* **The `:persistent_term` baseline is derived, not listed.**
  `capture_pristine!/0` snapshots every term this application owns —
  anything namespaced under `MediaCentaur*` — as the last act of
  `test_helper.exs`; `restore!/0` rewrites changed values, erases keys
  added since, and leaves dependencies' terms alone. A cache added
  tomorrow is covered without editing the module. Cost: ~2.6 µs per test.
* **It replaces the one-key mechanism it generalises.** `DataCase` used to
  restore `{MediaCentaur.Config, :config}` from a hand-made snapshot — the
  only cache anyone had been bitten by yet. That path is gone, not wrapped.
* **Two singletons are reset through their public API** — `Console.Buffer`
  (the ring buffer whose cross-test lines already forced one test to scope
  an assertion around it) and `IncomingLive.SearchSession` (a deliberate
  singleton that `/incoming` renders at mount).
* **The supervision tree is classified, and the test fails when it grows.**
  Stores can be swept by namespace; processes cannot. `dispositions/0`
  names all 22 children of `MediaCentaur.Supervisor` as `:sandboxed`,
  `:stateless`, `:reset`, or `:accepted` **with the reason**, and
  `global_state_sandbox_test.exs` fails on any child that isn't there. That
  is the stage's actual bar: a new stateful singleton is *caught*, not
  remembered.
* **Six files lost their private workarounds** — `incoming_live_test`,
  `incoming_live_pursuit_modal_test`, `watcher_test`, `console_test`,
  `capabilities_test`, `queue_monitor_test` each hand-rolled a save/restore
  or a defensive reset for exactly these caches. Deleting them is the proof
  the mechanism owns the concern rather than sitting beside it. (One of
  them was a `Capabilities` DB write inside `on_exit` — the thing MC0018
  exists to stop.)

### What this does not close

The `:accepted` rows are real exposure, written down instead of fixed:
`TMDB.MetadataStats` accumulates from telemetry and has no reset API — and
`status_live_test` already avoids asserting on it, which is the tell.
`ErrorReports.Buckets`, `SelfUpdate.Updater`, and the two schedulers are
contained today by their tests using named instances, not by the sandbox.
None is reset; each says why. When one of them bites, the inventory is
where the answer already is.

Async tests are covered but not protected: resetting a shared process is
sound only because every writer of global state in this suite is
`async: false`. An `async: true` test that wrote one would have it cleared
underneath it by a concurrent test's setup. That is stated in the
moduledoc, not enforced.

### Verification

* The deterministic repro above: red before, green after.
* `global_state_sandbox_test.exs` — 7 tests covering restore, erase,
  leave-dependencies-alone, both singleton resets, and the two inventory
  guards.
* Full suite at the campaign's own seed (`--seed 508425 --max-cases 24`)
  and at a second seed.

### Original stage text (for reference)

Kept as written, including the two claims corrected above: the repro that
no longer reproduces, and the GenServer that was never running.

#### Why it belongs to this campaign

Same class as Stage 7, one layer over. Stage 7: JS tests inherited another
file's `globalThis.window`, so results depended on load order. Stage 9: Elixir
tests inherit another test's GenServer state, so results depend on
*interleaving*. Both are **state living outside the isolation mechanism**, and
both report success until the order changes. The `DataCase` sandbox is
airtight for rows and has no opinion at all about process state.

#### Evidence (measured 2026-08-06)

**Deterministic reproduction.** Not a rate-based flake — a function of seed ×
test-count × `max_cases`. On clean `main`, add five inert tests and run one
seed:

```elixir
# test/media_centaur/zz_ordering_probe_test.exs
defmodule MediaCentaur.ZzOrderingProbeTest do
  use ExUnit.Case, async: true
  test "a", do: assert(1 == 1)   # ×5
end
```

```bash
mix test --seed 508425 --max-cases 24     # → 1 failure, every time
```

Five tests that assert **nothing** trigger it. That is the proof it is
ordering and not anyone's change.

**The failure.** `incoming_live_test.exs` *"empty Activity and History tabs
say so instead of rendering a void"*:

```elixir
assert has_element?(view, "[data-component='zone-empty']", "Nothing in flight")
```

**The mechanism**, from instrumenting the assertion and re-running the repro:

```
PROBE download_client_ready=true      # capability is fine
PROBE queue_monitor_items=3           # ← three leftover queue items
PROBE pursuit_rows_in_db=0            # ← the DB is clean; the sandbox worked
PROBE has_orphan_zone=true
```

`Downloads.QueueMonitor` is a GenServer holding the live download-client
queue. Its state survives every test boundary. `IncomingLive` renders
`QueueMatcher.match(view.in_flight, active_queue)` — with `in_flight == []`
(DB correctly empty) and three stale queue items, all three become **orphans**,
so `activity_empty?` is false and the empty-state line never renders
(`incoming_live.ex:750`, `:804`).

**The first hypothesis was wrong, and measuring is what caught it.**
`activity_empty?` is gated on `download_client_ready`, which reads a
`:persistent_term` cache (`capabilities.ex:33`) — global state outside the
sandbox, an irresistible culprit. The probe says `download_client_ready=true`
and the cache key is `:__unset`, i.e. computed from the DB every call and
correctly sandboxed. **Capabilities are innocent.** This is the campaign's
clause 5 collecting a fifth scalp inside the session that wrote it.

#### The decision this needs

The narrow fix is one line — reset `QueueMonitor` in `DataCase` setup. The
question is whether to stop there:

1. **Just `QueueMonitor`.** Smallest change, kills the known failure. Leaves
   every other stateful process in the tree with the same hole.
2. **Every global process a test can perturb.** Find them, reset them all in
   one place. Larger, and the list has to be derived from the supervision
   tree rather than guessed — Stage 2's lesson: *derive costs from the tool,
   not from a table.*
3. **Make the hole impossible.** A `DataCase` that resets registered
   stateful processes by default, so a new GenServer is covered without
   anyone remembering. This is Stage 7's move (cover the tree, not a list),
   and it is the one consistent with everything else this campaign chose.

**A count is not a fix** (clause 4), so do not let "how many GenServers"
decide it. The prior question is whether per-test process reset is even the
right shape, or whether the honest fix is that these tests should not depend
on process state at all.

#### Verification bar

The stage is done when the repro command **passes**, and when a *new* stale
GenServer would be caught rather than remembered. Re-run the exact repro
above — a green full suite proves nothing here, since the suite was green on
most seeds throughout.

**Do not weaken the assertion.** The test is right: an empty Activity tab
should say so. The leak is the defect.

## Completion criteria

* Stages 1–5 each either **resolved** or **explicitly declined** with
  the reason recorded in *Decisions made*. A declined stage is a valid
  outcome; an undiscussed one is not.
  **Status: ✅ 1, 2, 4, 5 resolved · 3 declined.**
* **Stage 6 resolved** — four items shipped, one already shipped by Stage 5,
  one dropped with its reason recorded in the stage. ✅
* **Closing the campaign does not require `/reconcile` to be fixed.** That
  defect was found here but belongs to no stage; carry it forward as
  ordinary work rather than letting it hold the campaign open.
  **It was fixed anyway** (`2e4aa4d7`), along with two further defects. ✅
* **Stages 7 and 8 each resolved or explicitly declined**, same rule as the
  original six. Stage 7 needed no conversation; Stage 8 was not started
  before its open questions were answered.
  **Status: ✅ both resolved.**
* **Stage 9 resolved or explicitly declined**, same rule. Its diagnosis needs
  no conversation — it was measured — but its *scope* is a decision, and the
  stage says not to let a GenServer count make it.
  **Status: ✅ resolved.** The scope decision was made for it by the corrected
  diagnosis: with no process holding the state, the choice was never between
  one GenServer and many, it was between one hand-named cache key and every
  key the app owns. The derived baseline covers the second, and the
  supervision-tree inventory covers the processes the sweep cannot reach —
  with four children accepted on the record rather than silently.
* `mix precommit` green after each stage, no new Credo suppressions.
  **Stage 7 changed what this criterion asserts**: before it, "precommit
  green" excluded `assets/js/hooks/` entirely, and every earlier stage's
  green was that narrower claim. None of them touched that directory, so
  none is in doubt. From Stage 7 on it covers `assets/js/` whole, and CI
  makes the same claim precommit does. ✅
  **And Stage 9 narrowed what it is worth, then widened it back a little**:
  a green run was a green *seed* — the suite passed on nearly every seed
  while carrying an order-dependent failure the whole time. With the term
  store restored per test, one large class of ordering dependence is gone;
  the `:accepted` processes in the inventory are what is left, and they are
  named.
* No stage left half-applied — the audit's own headline finding was
  that this repo's defects come from refactors that start well and stop
  at 80%. Stage 8 was the clearest chance to do it, where converting the two
  loud sites and leaving the three quiet ones would have looked finished; all
  five are settled, four changed and one exempted on the record. **Stage 9 is
  the next chance**, and option 1 in it (reset the one GenServer we caught) is
  precisely the shape of an 80% stop. **It took it**: the mechanism is derived
  from the namespace rather than from the one key we were bitten by, and the
  six files that hand-rolled their own version of it were emptied rather than
  left beside it.
* Stage 6 items are droppable; do not let them hold the campaign open.
  **Neither did** — both became stages and both are done.
* **MC0023's grandfather list does not hold this campaign open**, but it
  must not be forgotten either. 23 test files still build state with an
  inline `Repo` write because their schema has no `TestFactory` builder
  yet. The check makes the debt visible and stops it growing; shrinking
  it is ordinary work for whoever next touches one of those files —
  add the builder, convert the file, remove the entry. The list may only
  shrink. If it is still 23 entries in a few months, that is the signal
  it needed its own stage rather than a backlog.

## Pointers

* Audit sweep and all evidence: this campaign's originating session,
  2026-08-05 → 2026-08-06. Commits `f1050227`, `a0668da7`, `18950c88`,
  `7c91a459`, `914e94c9`.
* [ADR-029](../decisions/architecture/2026-03-26-029-data-decoupling.md) — Boundary as the dependency list (Stage 2)
* [ADR-030](../decisions/architecture/2026-04-02-030-liveview-logic-extraction.md) — LiveViews are thin wiring
* [ADR-041](../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md) — projection architecture (context for the Detail work already done)
* [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md) — campaign conventions, amended 2026-08-06
* [UIDR-012](../decisions/user-interface/2026-05-20-012-desktop-app-rendering-defaults.md) — desktop rendering defaults (cited as ADR-012 for months; see *Decisions made*)
* `.claude/skills/coding-guidelines/SKILL.md` — modular-cohesion rule quoted in Stage 1; *Lookup Naming Contract* added by Stage 4
* `credo_checks/{lookup_naming_contract,no_repo_setup_in_tests,no_markup_substring_assertion}.ex` — Stage 4's three checks; each moduledoc is the rule's spec, and `.credo.exs` carries the one-paragraph why beside each registration
* `test/support/factory.ex` — Stage 4's forced-setup helpers (`force_attrs/2`, `backdate/3`, `force_state/2`, `force_where/2`)
* `assets/js/input/core/dom_adapter.js` + `assets/js/input/config.js` — how nav items and layout keys resolve; read together with `Layouts.app/1` / `Layouts.input_system_root/1`, which mount the `#input-system` hook a page needs before any of it applies (Stage 3, declined; also where the `/reconcile` defect lives)
* `docs/architecture.md` — bounded contexts (Stage 2); PubSub taxonomy now lives in the `MediaCentaur.Topics` moduledoc (Stage 5)
* `credo_checks/native_confirm_dialog.ex` — Stage 8's MC0027; its moduledoc carries the three-way confirmation rule and the console exemption
* Stage 9's map: `test/support/global_state_sandbox.ex` (the mechanism and the supervision-tree inventory), `test/media_centaur/global_state_sandbox_test.exs` (including the guard that fails when the tree grows an unclassified child), `lib/media_centaur/downloads/queue_monitor.ex` (`store_and_broadcast/1` writes the leaking cache; the module itself never runs under `:test`), `lib/media_centaur_web/live/incoming_live.ex:750` + `:804` (where orphans defeat `activity_empty?`), `lib/media_centaur/capabilities.ex:33` (the cache that looked guilty and is not)
* [ADR-049](../decisions/architecture/2026-05-22-049-testing-principles.md) — owned async / testing principles, the nearest existing statement of what Stage 9 is really about
