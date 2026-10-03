# The Discovery Context Becomes Watchlist — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The bounded context that holds title intents is named for its surface (ADR-075 rule 3): `MediaCentaur.Discovery` becomes `MediaCentaur.Watchlist`, its topic `discovery:updates` becomes `watchlist:updates`, and every alias, Boundary dep, doc and decision record follows. No behaviour changes. `Pipeline.Discovery` (file discovery) is a different context and is untouched.

**Architecture:** A rename in three commits that each have one reason to exist: (1) the code — modules, files, aliases, Boundary deps, the topic, the factory and the tests that name them; (2) the context-map branch's tests and snapshot, which name the old file paths as fixtures — a separate commit so it drops cleanly if the owner rebases this branch onto `main` (as `b7b108ae` did for Phase 2); (3) prose — moduledocs that say "Discovery" meaning this context, the glossary, `docs/architecture.md`, `docs/social.md`, ADR-075 (second application), ADR-066 (amendment), the campaign.

**Tech Stack:** Elixir, Boundary, ExUnit, the context-map analyzer under `context_map/`.

Campaign: [`campaigns/social-and-watchlist.md`](../../../campaigns/social-and-watchlist.md), Phase 3. Run every `mix` command through `~/scripts/agents/agent-mix`. Use `git mv` for every rename so history follows.

**Names.** `MediaCentaur.Watchlist`, `Watchlist.TitleIntent`, `Watchlist.Events`, `Watchlist.Events.RungChanged`, `Watchlist.Titles`, `Watchlist.TmdbReferences`. Public function names do not change (`put_rung/3`, `list_watchlist/0`, `listed?/2`, `get_intent/2`, `rung/2`, `rungs/0`, `grabs?/2`, `subscribe/0`, the `ref/0` type). The topic is `watchlist:updates`, read through `Topics.watchlist_updates/0`. The `title_intents` table keeps its name. No existing module is `MediaCentaur.Watchlist` or aliases to a bare `Watchlist` (checked 2026-10-03: `WatchlistToggle`, `WatchlistRows`, `ShareWatchlist`, `WatchlistAutoRemove` are the neighbours; none collides).

**Out of scope.** `Pipeline.Discovery` and every "Discovery" that means file discovery (`lib/media_centaur/pipeline/**`, `review.ex`, `watcher/rescan.ex`, `episode_mapping/spine.ex`, `diagnostics_badge.ex`, `status_widgets/pipeline.ex`, the glossary rows *Settled*, *Match*, *Startup recovery*, `.credo.exs:366`); `docs/superpowers/**`, `docs/plans/**`, retired campaigns and `CHANGELOG.md` (history); the wiki (nothing there names the context).

---

## File map

| Was | Becomes |
|---|---|
| `lib/media_centaur/discovery.ex` (`MediaCentaur.Discovery`) | `lib/media_centaur/watchlist.ex` (`MediaCentaur.Watchlist`) |
| `lib/media_centaur/discovery/{events,title_intent,titles,tmdb_references}.ex` (`Discovery.*`) | `lib/media_centaur/watchlist/…` (`Watchlist.*`) |
| `test/media_centaur/discovery_test.exs` (`MediaCentaur.DiscoveryTest`), `test/media_centaur/discovery/title_intent_test.exs` (`MediaCentaur.Discovery.TitleIntentTest`) | `test/media_centaur/watchlist_test.exs` (`MediaCentaur.WatchlistTest`), `test/media_centaur/watchlist/title_intent_test.exs` (`MediaCentaur.Watchlist.TitleIntentTest`) |
| `Topics.discovery_updates/0`, `"discovery:updates"` | `Topics.watchlist_updates/0`, `"watchlist:updates"` |
| `alias MediaCentaur.Discovery…` / bare `Discovery.` in every file below | `alias MediaCentaur.Watchlist…` / `Watchlist.` |

Files that alias or name the context (the list `grep -rln "MediaCentaur\.Discovery\b" lib test config` gives on 2026-10-03, minus `test/context_map/`):

`lib/media_centaur/{acquisition.ex, acquisition/{drop_planner,mode_reconciler,targeting}.ex, acquisition/plans/gate.ex, activities.ex, activities/publisher.ex, release_tracking.ex, release_tracking/upcoming_feed.ex}`, `lib/media_centaur_web.ex` (Boundary deps), `lib/media_centaur_web/components/{release_tracking/tracking_detail, social/feed_entry, title/detail, title/logic, title/tracking_controls, title/watchlist_toggle}.ex`, `lib/media_centaur_web/live/{incoming_live.ex, incoming_live/watchlist_rows.ex, social_live.ex, social_live/feed_entries.ex, title_detail_host.ex, title_detail_host/acquisition.ex}`, `config/config.exs:183` (`:tmdb_reference_providers`), `test/support/factory.ex:15`, and the tests `test/media_centaur/{acquisition/pursuits/commands/terminal_commands, credo/checks/tmdb_detail_seam, release_tracking/{movies_added,reconcile,set_rung}, tmdb/references}_test.exs`, `test/media_centaur_web/{live/{incoming_live, incoming_live/view, incoming_live/watchlist_rows, library_live, library_live_tracking, social_live}_test.exs, page_smoke_test.exs}`.

Files that use a bare `Discovery` alias without the full name (follow the alias): `lib/media_centaur_web/live/title_detail_host.ex:148` (`@topics`), `lib/media_centaur_web/live/incoming_live.ex:188` (the subscribe list), `lib/media_centaur_web/live/social_live.ex:112`, `lib/media_centaur/acquisition/targeting.ex:222` (fully qualified call), `lib/media_centaur_web/components/title/detail.ex:88` and `lib/media_centaur_web/live/incoming_live/watchlist_rows.ex:30` (fully qualified types).

---

### Task 1: The code is `MediaCentaur.Watchlist`

**Files:** the file map, every file in the two lists above, `lib/media_centaur/topics.ex:60,169`.

- [ ] **Step 1: Tests first.** `git mv test/media_centaur/discovery_test.exs test/media_centaur/watchlist_test.exs`; `git mv test/media_centaur/discovery test/media_centaur/watchlist`. Across `test/` **excluding `test/context_map/`**, replace `MediaCentaur.Discovery` → `MediaCentaur.Watchlist`, `MediaCentaur.DiscoveryTest` → `MediaCentaur.WatchlistTest`, and the bare alias uses `Discovery.` → `Watchlist.` in files that alias the context (not `Pipeline.Discovery.`), plus `discovery_updates` → `watchlist_updates` and `discovery:updates` → `watchlist:updates`:

```sh
cd ~/src/media-centaur/media-centaur-app
files=$(grep -rl "MediaCentaur\.Discovery\b" test --exclude-dir=context_map)
sed -i 's/MediaCentaur\.DiscoveryTest/MediaCentaur.WatchlistTest/g; s/MediaCentaur\.Discovery\b/MediaCentaur.Watchlist/g' $files
# bare alias uses: only in files that aliased the context; Pipeline.Discovery lines are excluded by the negative match
for f in $files; do sed -i -E '/Pipeline\.Discovery/! s/\bDiscovery\./Watchlist./g' "$f"; done
grep -rl "discovery_updates\|discovery:updates" test --exclude-dir=context_map | xargs -r sed -i 's/discovery_updates/watchlist_updates/g; s/discovery:updates/watchlist:updates/g'
```

Then by hand: `test/support/factory.ex` section header `# Discovery (title intents)` → `# Watchlist (title intents)` and its comment "`Discovery.put_rung/3`'s two branches" → `Watchlist.put_rung/3`; `test/support/task_awaits.ex:8,16` (`Discovery.put_rung/3` → `Watchlist.put_rung/3`). Check the diff: every changed `Discovery.` was this context (`git diff --stat test; git diff test | grep "^[-+].*Discovery" | grep -v Watchlist`). Run `~/scripts/agents/agent-mix test test/media_centaur/watchlist_test.exs` — fails: `module MediaCentaur.Watchlist is not available`.

- [ ] **Step 2: Implement.**

```sh
git mv lib/media_centaur/discovery.ex lib/media_centaur/watchlist.ex
git mv lib/media_centaur/discovery lib/media_centaur/watchlist
files=$(grep -rl "MediaCentaur\.Discovery\b" lib config)
sed -i 's/MediaCentaur\.Discovery\b/MediaCentaur.Watchlist/g' $files
for f in $files; do sed -i -E '/Pipeline\.Discovery/! s/\bDiscovery\./Watchlist./g' "$f"; done
grep -rl "discovery_updates\|discovery:updates" lib | xargs -r sed -i 's/discovery_updates/watchlist_updates/g; s/discovery:updates/watchlist:updates/g'
```

Then by hand, the bare-alias sites (`title_detail_host.ex:148`, `incoming_live.ex:188`, `social_live.ex:112`: `Discovery` → `Watchlist` in the module lists), and `lib/media_centaur/topics.ex:60`'s table row, which is also stale about the message:

```markdown
| `watchlist:updates` | `Watchlist.Events` | `{:title_intent_changed, %RungChanged{}}` — one message: a rung moved (ADR-060 typed struct) |
```

`lib/media_centaur/watchlist.ex`'s moduledoc opens with the one-sentence purpose (ADR-075 rule 2):

```elixir
  @moduledoc """
  The watchlist: the **title intents** a person holds — one record per
  title, carrying the rung that says what the app should do about that
  title's releases — and, in later iterations, the candidate sources
  that feed them (TMDB discover, list import, friend reviews). Shown
  whole on Incoming's Watchlist tab (UIDR-050).

  A record here is the only authored thing in the whole tracking story.
  Watchlist stores the rung and knows nothing about what it causes: no
  calendars, no wants, no grabs. `ReleaseTracking.set_rung/3` is the one
  write path, because deriving the machinery needs to see both sides, and
  the dependency runs that way (ADR-066).

  Accepts `MediaCentaur.TMDB.Title` at the boundary — the app-wide title
  value every candidate source produces (converged 2026-09-02; see
  docs/superpowers/specs/2026-09-02-friends-recommendations-design.md).
  A record keeps only that title's identity: the snapshot a listed title
  is painted from is the TMDB store's, attached on every read by
  `Watchlist.Titles` (ADR-071).

  Named `Discovery` until 2026-10-03 (ADR-075 rule 3: a context carries
  its surface's name). `Pipeline.Discovery` — file discovery — is a
  different context.
  """
```

and `put_rung/3`'s doc: "This is Watchlist's write, not the app's: raising a rung has consequences Watchlist must not know about". Other moduledoc/comment lines in these files that say "Discovery" meaning this context follow: `watchlist/title_intent.ex:52` ("because Watchlist and Activities are independent contexts"), `watchlist/events.ex:3` (the topic name, done by sed), `release_tracking.ex:469-470`, `activities.ex:498`, `acquisition/title_states.ex:4` ("watchlist rows and the title detail modal"), `activities/publisher.ex:9` (topic, sed), `title_detail_host.ex:76` (topic, sed), `incoming_live.ex:186` (topic, sed).

`grep -rn "MediaCentaur\.Discovery\b\|discovery_updates\|discovery:updates" lib config test --exclude-dir=context_map` must be empty, and `grep -rn "\bDiscovery\b" lib config test --exclude-dir=context_map | grep -v "Pipeline\|pipeline/\|review\.ex\|review_test\|rescan\|spine\|diagnostics_badge\|status_widgets\|until 2026-10-03"` must show only file-discovery sentences.

- [ ] **Step 3: Green.** `~/scripts/agents/agent-mix compile --warnings-as-errors` (Boundary recompiles the deps lists), then `~/scripts/agents/agent-mix test test/media_centaur/watchlist_test.exs test/media_centaur/watchlist test/media_centaur/release_tracking test/media_centaur/activities test/media_centaur/tmdb/references_test.exs test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/live/social_live_test.exs test/media_centaur_web/live/title_detail_host_test.exs test/media_centaur_web/page_smoke_test.exs`. `~/scripts/agents/agent-mix format`.

- [ ] **Step 4: Commit** `refactor: the Discovery context is Watchlist — MediaCentaur.Watchlist, watchlist:updates (ADR-075 rule 3)`. The context-map tests are red at this commit by design; Task 2 is the next commit.

---

### Task 2: The context-map tests and snapshot follow (droppable commit)

**Files:** `test/context_map/{contexts,sources,schemas,fixture_instances,html,report,finding}_test.exs`, `test/context_map/rules/{cross_context_key,foreign_field,reinterpretation}_test.exs`, `docs/context-map/context-map.json`.

Why separate: these files exist only on the `context-map` branch this campaign branch forked from. If the owner rebases onto `main` (`git rebase --onto main 7544b939`), this commit and `b7b108ae` are dropped; if the owner merges `context-map`, both stay.

- [ ] **Step 1: Red.** `~/scripts/agents/agent-mix test test/context_map/contexts_test.exs test/context_map/sources_test.exs test/context_map/schemas_test.exs test/context_map/fixture_instances_test.exs` — fail (`Enum.find` returns nil for `MediaCentaur.Discovery`; `File.read!` on the old path; findings keyed by `MediaCentaur.Watchlist.TitleIntent`).

- [ ] **Step 2: Rename in the fixtures.**

```sh
sed -i 's/MediaCentaur\.Discovery\b/MediaCentaur.Watchlist/g; s#lib/media_centaur/discovery#lib/media_centaur/watchlist#g' test/context_map/*.exs test/context_map/rules/*.exs
sed -i 's/\bdiscovery\b/watchlist/g; s/@discovery/@watchlist/g; s/by Discovery/by Watchlist/g; s/which Discovery/which Watchlist/g; s/lists Discovery/lists Watchlist/g' test/context_map/contexts_test.exs test/context_map/fixture_instances_test.exs test/context_map/rules/foreign_field_test.exs
```

Read the diff: a test title such as "lists Discovery with its deps and prefixed exports" reads "lists Watchlist …"; no synthetic fixture lost a distinct name. `~/scripts/agents/agent-mix test test/context_map` — green.

- [ ] **Step 3: The snapshot.** `~/scripts/agents/agent-mix context_map` regenerates `docs/context-map/context-map.json` (its paths currently still say `components/discovery/*` from before Phase 2; this is the first regeneration since). If the task writes anything other than the two JSON files, `git checkout` the rest. `git diff --stat docs/context-map`.

- [ ] **Step 4: Commit** `test(context_map): follow the Watchlist rename; regenerate the snapshot`.

---

### Task 3: Prose, records, the glossary, the campaign

**Files:**
- Amend: `decisions/architecture/2026-09-29-075-bounded-context-naming.md` (second application + dated amendment), `decisions/architecture/2026-09-07-066-one-ladder-per-title.md` (rule 8 names `Discovery` three times; amendment)
- Docs: `docs/architecture.md:81` (the contexts table row — also stale: it says `watchlist_items` table and the old message names), `docs/social.md:33-48,50` (the dependency sentence, the contexts table row, "The Discovery/Activities separation"), `docs/GLOSSARY.md` rows **Title intent** (l.68), **Ignored** (l.70), **Following** (l.77), **Listing** (l.224), and a new row **Watchlist** (context) after **Watchlist** (tab)
- Campaign: `campaigns/social-and-watchlist.md`, `campaigns/README.md:31` if it reads as future tense

- [ ] **Step 1: ADR-075.** After "First application: …" add:

```markdown
Second application (2026-10-03): `Discovery` becomes `Watchlist` — "The watchlist: the title intents a person holds." Rule 3: its one surface is Incoming's Watchlist tab (UIDR-050). `Pipeline.Discovery`, file discovery, is a different context and keeps its name.
```

ADR-066, after rule 9's paragraph and before the 2026-09-28 amendment:

```markdown
**Amendment 2026-10-03.** `Discovery` in rules 1–9 is the context now named `MediaCentaur.Watchlist` (ADR-075, second application); the rules stand unchanged.
```

Run `scripts/gen-decisions-index` (adds `amended:` frontmatter only if the script expects it — follow what UIDR-050's amendment did).

- [ ] **Step 2: Docs.** `docs/architecture.md:81`:

```markdown
| `MediaCentaur.Watchlist` | `title_intents` table | The watchlist — one title intent per title, carrying the rung (Ignored, List, Follow, Grab) that says what the app should do about the title's releases; shown whole on Incoming's Watchlist tab. Broadcasts `{:title_intent_changed, %RungChanged{}}` on `watchlist:updates`. Named `Discovery` until 2026-10-03 (ADR-075). |
```

`docs/social.md`: the dependency sentence `Discovery ← Activities` → `Watchlist ← Activities`, "`Library`, `WatchHistory`, `Watchlist` and `Settings.Preferences`"; the table row:

```markdown
| `MediaCentaur.Watchlist` | The watchlist (`title_intents`). Knows nothing about the friend network — a `:friend` record stores a bare `activity_id`. | `Library`, `TmdbArtwork`, `TMDB` |
```

and "The Watchlist/Activities separation is deliberate: a title intent records *intent*, …". Glossary: `Discovery.TitleIntent` → `Watchlist.TitleIntent`, `Discovery.Titles` → `Watchlist.Titles`, `Discovery.list_watchlist/0` → `Watchlist.list_watchlist/0`, `Discovery.Events.RungChanged` → `Watchlist.Events.RungChanged` (twice); "Formerly `Discovery.WatchlistItem`" stays (history). New row after l.76:

```markdown
| **Watchlist** (context) | `MediaCentaur.Watchlist`: the bounded context that holds **title intents** and nothing else — the rung, provenance, the TMDB identity; no calendars, wants or grabs (ADR-066). Its topic is `watchlist:updates`. Named `Discovery` until 2026-10-03 (ADR-075 rule 3: a context carries its surface's name — the tab above). `Pipeline.Discovery`, file discovery, is unrelated. |
```

`grep -rn "MediaCentaur\.Discovery\b\|Discovery\.TitleIntent\|Discovery\.Events\|Discovery\.Titles\|Discovery\.list_watchlist\|Discovery\.put_rung\|discovery:updates" docs decisions .claude README.md campaigns priv --exclude-dir=superpowers --exclude-dir=plans` must return only ADR-066's amended text, ADR-075's application line, the glossary's "Formerly" and "Named `Discovery` until" phrases, and retired campaigns.

- [ ] **Step 3: Campaign.** `campaigns/social-and-watchlist.md`: Status → "Phases 1–3 done …; Phase 4 next"; Next steps 3 → done 2026-10-03 with the plan path and the three commits; Decisions: a dated line that the context-map test changes are a separate droppable commit, and that this phase ran inline (a mechanical rename) with one whole-slice review rather than per-task subagents; Completion criteria: "`MediaCentaur.Discovery` does not exist" — met. Update `last_updated`.

- [ ] **Step 4: Commit** `docs: the Watchlist context — ADR-075 second application, ADR-066 amendment, glossary, architecture, social docs, campaign`.

---

### Task 4: Precommit, a look, review

- [ ] `~/scripts/agents/agent-mix precommit` clean (it includes `mix boundaries` and the full suite).
- [ ] With the dev server up (it serves this checkout; the code reloader picks up the rename): `~/scripts/agents/page-shot --url http://127.0.0.1:2160/incoming --viewport 1920x1080 --wait-ms 4000` renders the Watchlist tab; `~/scripts/agents/mc-eval 'MediaCentaur.Watchlist.list_watchlist() |> length()'` answers (the dev node has the module).
- [ ] One `superpowers:code-reviewer` pass over `git diff 043827a3..HEAD` with this plan as the spec: anything named `Discovery` that meant title intents and survived; any `Pipeline.Discovery` reference that was renamed by mistake; any doc that now says `Watchlist` meaning the tab where the context was meant.
