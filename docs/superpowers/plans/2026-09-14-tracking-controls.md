# Tracking Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the seven-way tracking pill with the bookmark and two switches (Track release dates, Auto-grab), shrink the ladder to Ignored · List · Follow · Grab, and make the Download button's planning mode the one answer to "does a tracking plan commit alone?".

**Architecture:** The record (`Discovery.TitleIntent`) keeps one rung; `:ask` and `:default` are deleted and `grabs?/1` replaces `grab_mode/2`. The approval policy for every plan comes from `Settings.Preferences.PlanningMode.approval_policy/1`; `AutoGrabSettings.default_mode` and its Settings row go. `Components.Title.TrackingControls` renders two Settings-kit toggle rows over the record; `WatchlistToggle` removes at any rung. A data migration folds old rungs into the new set.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto (SQLite via ecto_sqlite3), Phoenix Storybook, ExUnit. Spec: `docs/superpowers/specs/2026-09-14-tracking-controls-design.md`.

**Conventions for every task:** run mix through `~/scripts/agents/agent-mix` (never bare `mix`). Test-first. Commit after each task with a conventional message ending in the session trailer:

```
Claude-Session: https://claude.ai/code/session_014xQc6Bh4f1qNaLESsiQmAV
```

Work on `main`; do not push.

---

## File map

| File | Responsibility after this plan |
|---|---|
| `lib/media_centaur/discovery/title_intent.ex` | Four rungs; `grabs?/1` |
| `lib/media_centaur/discovery.ex` | `grabs?/2` replaces `grab_mode/3` |
| `lib/media_centaur/settings/preferences/planning_mode.ex` | Owns `approval_policy/1` |
| `lib/media_centaur_web/live/plan_flow.ex` | Loses `approval_policy/1` |
| `lib/media_centaur/acquisition/auto_grab_settings.ex` | Loses `default_mode` |
| `lib/media_centaur_web/live/settings_live/acquisition_section.ex`, `settings_live.ex` | Lose the "When a release appears" row |
| `priv/repo/data_migrations/20260914120000_tracking_is_two_switches.exs` | Folds `ask`/`default` rungs; deletes the setting |
| `lib/media_centaur/acquisition/{drop_planner,mode_reconciler,targeting}.ex`, `acquisition/reactor/handlers.ex` | Read `Discovery.grabs?/2`; policy from planning mode |
| `lib/media_centaur/release_tracking/upcoming_feed.ex` | Context key `planning_mode` |
| `lib/media_centaur_web/components/release_tracking/tracking_detail.ex` | Context key `planning_mode`; no `default_grab_mode` field |
| `lib/media_centaur_web/components/title/logic.ex`, `detail.ex` | `release_ahead?/3`; markers; detail carries `release_ahead?` |
| `lib/media_centaur_web/components/settings.ex` | `settings_row/1` gains `id` and `disabled?` |
| `lib/media_centaur_web/components/title/tracking_controls.ex` (new) | The two rows |
| `lib/media_centaur_web/components/title/intent_control.ex` (deleted) | — |
| `lib/media_centaur_web/components/title/watchlist_toggle.ex` | Off at any listed rung |
| `lib/media_centaur_web/components/title/detail_modal.ex`, `components/detail_panel.ex` | Mount the new component |
| `lib/media_centaur_web/live/{title_detail_host,entity_modal,discovery_live,incoming_live,home_live,library_live}.ex`, `incoming_live/view.ex`, `components/acquisition/media_results.ex` | Drop the global mode; carry `planning_mode`; release window on the host |
| `lib/media_centaur/showcase.ex` | Seeds at `:grab` |
| Stories under `storybook/title/`, `storybook/settings/`, `storybook/acquisition/`, `storybook/detail_panel/` | Fixtures on the new rung set |
| `decisions/user-interface/2026-09-14-042-tracking-is-the-bookmark-and-two-switches.md` (new), UIDR-036 amendment, `docs/GLOSSARY.md`, wiki, `CHANGELOG.md` | Records |

---

### Task 1: The ladder shrinks to four rungs

**Files:**
- Modify: `lib/media_centaur/discovery/title_intent.ex`
- Test: `test/media_centaur/discovery/title_intent_test.exs`

- [ ] **Step 1: Rewrite the failing tests**

Replace the `describe "the ladder"` and `describe "grab_mode/2"` blocks in `test/media_centaur/discovery/title_intent_test.exs` with:

```elixir
  describe "the ladder" do
    test "runs Ignored · List · Follow · Grab, and Off is not on it" do
      assert TitleIntent.rungs() == [:ignored, :list, :follow, :grab]
      refute :off in TitleIntent.rungs()
    end

    test "rung_at_least?/2 orders the ladder" do
      assert TitleIntent.rung_at_least?(:follow, :follow)
      assert TitleIntent.rung_at_least?(:grab, :follow)
      refute TitleIntent.rung_at_least?(:list, :follow)
    end

    test "Ignored is a record below List — an opinion, unlike Off, but not on the list" do
      refute TitleIntent.rung_at_least?(:ignored, :list)
      assert TitleIntent.rung_at_least?(:ignored, :ignored)
      assert TitleIntent.rung_at_least?(:list, :ignored)
      refute TitleIntent.follows_releases?(:ignored)
    end

    test "a title with no record is below every rung" do
      assert TitleIntent.rung_at_least?(nil, :list) == false
      assert TitleIntent.rung_at_least?(nil, :follow) == false
    end

    test "following starts at Follow — List is on the list and nothing more" do
      refute TitleIntent.follows_releases?(:list)
      assert TitleIntent.follows_releases?(:follow)
      assert TitleIntent.follows_releases?(:grab)
      refute TitleIntent.follows_releases?(nil)
    end
  end

  describe "grabs?/1" do
    test "only Grab plans releases when they drop" do
      assert TitleIntent.grabs?(:grab)

      for rung <- [nil, :ignored, :list, :follow] do
        refute TitleIntent.grabs?(rung), "#{inspect(rung)} must never grab"
      end
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/discovery/title_intent_test.exs`
Expected: FAIL — `rungs/0` still returns six values; `grabs?/1` undefined.

- [ ] **Step 3: Change the schema**

In `lib/media_centaur/discovery/title_intent.ex`:

Replace the moduledoc's rung table and the two paragraphs after it with:

```elixir
  | rung | what the app does |
  |---|---|
  | *(no record)* | nothing; the title is not on your list |
  | `:ignored` | keeps it off the Feed, and nothing else |
  | `:list` | keeps it on your list, and nothing else |
  | `:follow` | keeps its calendar, so releases appear under Coming up |
  | `:grab` | plans each release when it drops; the person's planning mode says whether the plan commits by itself or waits for approval |

  **Off is the absence of a record, never a stored value.** That is what
  makes "turning tracking off deletes it" a property of the schema
  instead of a rule something has to remember to apply, and it is why
  there is no durable-disarm state to keep: nothing but a person can put
  a title back on the ladder, so nothing can silently re-arm it.

  **Ignored is a record, below List.** Off is no opinion; Ignored is the
  person's decision that the title is not for them, and the one thing it
  does is keep friends' reviews and listings of it off the Feed.
  Wanting the title later — any rung at List or above — replaces it,
  the way every other move on the ladder does.

  **There is no per-title grab policy.** Grab says the app plans the
  release; whether that plan commits alone or parks for review is
  `Settings.Preferences.PlanningMode`, the same answer the Download
  button gives (spec 2026-09-14). The `:ask` and `:default` rungs that
  used to carry a policy were folded into Grab and Follow by the
  `TrackingIsTwoSwitches` data migration.
```

Replace the rung list and type:

```elixir
  @rungs [:ignored, :list, :follow, :grab]

  @typedoc "Where a person's intent about a title sits. Off is no record at all."
  @type rung :: :ignored | :list | :follow | :grab
```

Replace the whole `grab_mode/2` doc + clauses with:

```elixir
  @doc """
  Whether the app plans the title's releases when they drop. Only Grab
  does; the rungs below keep a list or a calendar and nothing more. The
  one question acquisition asks about a title.
  """
  @spec grabs?(rung() | nil) :: boolean()
  def grabs?(:grab), do: true
  def grabs?(_rung), do: false
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur/discovery/title_intent_test.exs`
Expected: PASS. (The rest of the suite is red until later tasks; that is expected.)

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/discovery/title_intent.ex test/media_centaur/discovery/title_intent_test.exs
git commit -m "refactor(discovery): the ladder is Ignored · List · Follow · Grab; grabs?/1 replaces grab_mode/2"
```

---

### Task 2: `Discovery.grabs?/2` and `PlanningMode.approval_policy/1`

**Files:**
- Modify: `lib/media_centaur/discovery.ex:129-137`
- Modify: `lib/media_centaur/settings/preferences/planning_mode.ex`
- Modify: `lib/media_centaur_web/live/plan_flow.ex`
- Modify: `lib/media_centaur_web/live/title_detail_host.ex:454,462`
- Modify: `lib/media_centaur_web/live/entity_modal.ex:1147,1160`
- Modify: `lib/media_centaur/release_tracking.ex:159-175, 364-398`
- Test: `test/media_centaur/settings/preferences/planning_mode_test.exs`
- Test: `test/media_centaur/release_tracking/set_rung_test.exs:108-122`

- [ ] **Step 1: Write the failing tests**

Append to `test/media_centaur/settings/preferences/planning_mode_test.exs`, before `defp store`:

```elixir
  describe "approval_policy/1" do
    test "auto-select commits alone; manual select parks for review" do
      assert PlanningMode.approval_policy(:auto_select_best_release) == "automatic"
      assert PlanningMode.approval_policy(:manually_select_release) == "review"
    end
  end
```

Add to the `describe "a film you already own"` block in `test/media_centaur/release_tracking/set_rung_test.exs` (the file already imports `MediaCentaur.TestFactory` through `DataCase`; if not, add `import MediaCentaur.TestFactory`):

```elixir
    test "complete?/2 is the one spelling of the rule: an owned film, never a series" do
      movie = create_movie(%{name: "Owned Movie"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
      create_linked_file(%{movie_id: movie.id})

      assert ReleaseTracking.complete?(777, :movie)
      refute ReleaseTracking.complete?(778, :movie)
      refute ReleaseTracking.complete?(@tmdb_id, :tv_series)
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/settings/preferences/planning_mode_test.exs test/media_centaur/release_tracking/set_rung_test.exs`
Expected: FAIL — `approval_policy/1` and `complete?/2` undefined.

- [ ] **Step 3: Move the mapping down to the setting; one owned-film predicate**

In `lib/media_centaur/release_tracking.ex`, add after `reconcile_refs/1`:

```elixir
  @doc """
  Whether nothing is left to release: a film the library owns. The one
  spelling of the rule `derive/3` and `reconcile/2` apply — a tracked
  title exists only while the title is followed *and* incomplete — and
  the title view reads to show no tracking rows. A series is never
  complete, and neither is a collection: no movie owns a collection's id.
  """
  @spec complete?(integer(), Title.media_type()) :: boolean()
  def complete?(tmdb_id, :movie), do: ExternalIds.tmdb_owners([{tmdb_id, :movie}]) != %{}
  def complete?(_tmdb_id, :tv_series), do: false
```

In `reconcile_item/1` replace `not owned_film?(item)` with `not complete?(item.tmdb_id, item.media_type)` and delete both `owned_film?/1` clauses and their comment. In `derive/3` replace the `movie_in_library?(title) ->` clause head with `complete?(title.tmdb_id, title.media_type) ->` and delete both `movie_in_library?/1` clauses. Keep the comment above `derive/3`; change "a single film already in the library is complete" to "a film already in the library is complete (`complete?/2`)".

In `lib/media_centaur/settings/preferences/planning_mode.ex`, add after `other/1`:

```elixir
  @doc """
  The approval policy a plan made under `mode` carries: auto-select
  commits a clean plan with nobody looking; manual select parks it for a
  person. The one mapping, read by the Download button and by the drop
  planner alike (spec 2026-09-14) — a tracking plan asks first exactly
  when a manual download would.
  """
  @spec approval_policy(mode()) :: String.t()
  def approval_policy(:auto_select_best_release), do: "automatic"
  def approval_policy(:manually_select_release), do: "review"
```

Amend the moduledoc's first paragraph so it also says: "It is also the approval policy every tracking plan is stamped with (`approval_policy/1`)."

In `lib/media_centaur_web/live/plan_flow.ex`, delete the `approval_policy/1` doc, spec and clauses, and the `alias MediaCentaur.Settings.Preferences.PlanningMode` line if nothing else in the module uses it. Change the moduledoc's first sentence to: "The ending a download gets, in one place: the flash auto-select raises, and the words for each way planning can fail."

In `lib/media_centaur_web/live/title_detail_host.ex` replace both `PlanFlow.approval_policy(` with `PlanningMode.approval_policy(` (the alias exists at line 75).

In `lib/media_centaur_web/live/entity_modal.ex` add `alias MediaCentaur.Settings.Preferences.PlanningMode` next to the other aliases, change line 1147 to `mode = PlanningMode.value()`, and line 1160 to `opts = [approval_policy: PlanningMode.approval_policy(mode)]`.

In `lib/media_centaur/discovery.ex` replace the `grab_mode/3` doc, spec and clause with:

```elixir
  @doc "Whether the title auto-grabs — plans its releases when they drop. The one question acquisition asks about a title."
  @spec grabs?(integer(), media_type()) :: boolean()
  def grabs?(tmdb_id, media_type), do: TitleIntent.grabs?(rung(tmdb_id, media_type))
```

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/settings/preferences/planning_mode_test.exs test/media_centaur/release_tracking/set_rung_test.exs`
Expected: PASS (the set_rung tests that list `:ask`/`:default` still fail until Task 13; the new `complete?/2` test passes).

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/discovery.ex lib/media_centaur/release_tracking.ex lib/media_centaur/settings/preferences/planning_mode.ex lib/media_centaur_web/live/plan_flow.ex lib/media_centaur_web/live/title_detail_host.ex lib/media_centaur_web/live/entity_modal.ex test/media_centaur/settings/preferences/planning_mode_test.exs test/media_centaur/release_tracking/set_rung_test.exs
git commit -m "refactor: planning mode owns the approval policy; Discovery.grabs?/2; ReleaseTracking.complete?/2"
```

---

### Task 3: The global grab mode goes

**Files:**
- Modify: `lib/media_centaur/acquisition/auto_grab_settings.ex`
- Modify: `lib/media_centaur_web/live/settings_live/acquisition_section.ex:236-270`
- Modify: `lib/media_centaur_web/live/settings_live.ex:2865`
- Modify: `storybook/settings/settings_choice.story.exs:27`
- Test: `test/media_centaur/acquisition/auto_grab_settings_test.exs`

- [ ] **Step 1: Update the tests**

In `test/media_centaur/acquisition/auto_grab_settings_test.exs`:

- Delete `assert settings.default_mode == "all_releases"` from "returns built-in defaults".
- In "the struct carries no floor or patience field" add `refute Map.has_key?(%AutoGrabSettings{}, :default_mode)` and rename the test to "the struct carries no grab mode, floor or patience field".
- Delete the whole test "respects mode override".
- In "refuses a value outside the enum or off the ladder", replace `assert {:error, :invalid} = AutoGrabSettings.put(:default_mode, "sometimes")` with `assert {:error, :invalid} = AutoGrabSettings.put(:default_mode, "all_releases")` (an unknown field now).

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/auto_grab_settings_test.exs`
Expected: FAIL — the struct still has `default_mode`; `put(:default_mode, "all_releases")` returns `:ok`.

- [ ] **Step 3: Remove the field**

In `lib/media_centaur/acquisition/auto_grab_settings.ex`:

- Remove `"auto_grab.default_mode",` from `@keys`.
- Remove `default_mode: "all_releases",` from `@builtin_defaults` and the `- mode: "all_releases"` line from the moduledoc's fallback list.
- Remove `default_mode: ~w(all_releases ask off),` from `@allowed`.
- Remove `default_mode: "auto_grab.default_mode",` from `@storage_key`.
- Remove `@type mode :: String.t()`, drop `:default_mode` from `@type field`, and `default_mode: mode(),` from `@type t`.
- Remove the `default_mode:` line from `load/0`.

Add to the moduledoc after the first paragraph:

```
  There is no grab mode here. Whether a title auto-grabs is its rung
  (`Discovery.TitleIntent.grabs?/1`); whether the plan commits alone is
  the person's planning mode (`Settings.Preferences.PlanningMode`).
```

In `lib/media_centaur_web/live/settings_live/acquisition_section.ex`:

- Delete the whole `<.settings_choice id="auto-grab-default_mode" … />` element (lines 262-270).
- Change the Auto-acquisition card's description to `"Applied to every release auto-grab takes."`.
- Change the Download button card's `settings_choice` description to `"The other choice stays in the button's menu. Also decides whether auto-grab asks first."`.

In `lib/media_centaur_web/live/settings_live.ex` line 2865: `@auto_grab_fields ~w(default_max_quality size_preference pack_min_fit max_attempts)`.

In `storybook/settings/settings_choice.story.exs` line 27 replace the options fixture with `options: [{"uhd_4k", "4K"}, {"hd_1080p", "1080p"}],` and adjust that variation's `selected:` to `"uhd_4k"` and its `label:` to `"Highest resolution"` if the story names the old setting.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/auto_grab_settings_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/auto_grab_settings.ex lib/media_centaur_web/live/settings_live/acquisition_section.ex lib/media_centaur_web/live/settings_live.ex storybook/settings/settings_choice.story.exs test/media_centaur/acquisition/auto_grab_settings_test.exs
git commit -m "refactor(settings): drop the auto-grab default mode; planning mode is the one grab policy"
```

---

### Task 4: Data migration — ask and default fold into grab and follow

**Files:**
- Create: `priv/repo/data_migrations/20260914120000_tracking_is_two_switches.exs`
- Create: `test/media_centaur/repo/data_migrations/tracking_is_two_switches_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Repo.DataMigrations.TrackingIsTwoSwitchesTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.TrackingIsTwoSwitches
  alias MediaCentaur.Settings

  # The schema no longer admits the retired rungs, so the legacy state is
  # written the way the old app left it: straight into the column.
  defp legacy_rung!(tmdb_id, rung) do
    Repo.query!("UPDATE title_intents SET rung = ? WHERE tmdb_id = ?", [rung, tmdb_id])
    :ok
  end

  defp rungs do
    %{rows: rows} = Repo.query!("SELECT tmdb_id, rung FROM title_intents ORDER BY tmdb_id", [])
    Map.new(rows, fn [id, rung] -> {id, rung} end)
  end

  defp global_mode!(mode) do
    Settings.find_or_create_entry!(%{key: "auto_grab.default_mode", value: %{"value" => mode}})
  end

  setup do
    for {id, rung} <- [{1, :list}, {2, :follow}, {3, :grab}, {4, :grab}, {5, :ignored}] do
      create_title_intent(%{tmdb_id: id, media_type: :movie, name: "Movie #{id}", rung: rung})
    end

    legacy_rung!(3, "ask")
    legacy_rung!(4, "default")
    :ok
  end

  describe "sweep/1" do
    test "ask becomes grab; default becomes grab when the old setting grabbed; the setting goes" do
      global_mode!("all_releases")

      assert :ok = TrackingIsTwoSwitches.sweep(Repo)

      assert rungs() == %{1 => "list", 2 => "follow", 3 => "grab", 4 => "grab", 5 => "ignored"}
      assert Settings.get_by_key("auto_grab.default_mode") == nil
    end

    test "default becomes follow when the old setting was Notify only" do
      global_mode!("off")

      assert :ok = TrackingIsTwoSwitches.sweep(Repo)

      assert rungs()[4] == "follow"
      assert rungs()[3] == "grab"
    end

    test "default becomes grab when the old setting was Ask first, or absent" do
      global_mode!("ask")
      assert :ok = TrackingIsTwoSwitches.sweep(Repo)
      assert rungs()[4] == "grab"

      legacy_rung!(4, "default")
      assert :ok = TrackingIsTwoSwitches.sweep(Repo)
      assert rungs()[4] == "grab"
    end

    test "is idempotent" do
      global_mode!("off")
      assert :ok = TrackingIsTwoSwitches.sweep(Repo)
      before = rungs()
      assert :ok = TrackingIsTwoSwitches.sweep(Repo)
      assert rungs() == before
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/repo/data_migrations/tracking_is_two_switches_test.exs`
Expected: FAIL — module `TrackingIsTwoSwitches` not found.

- [ ] **Step 3: Write the migration**

`priv/repo/data_migrations/20260914120000_tracking_is_two_switches.exs`:

```elixir
defmodule MediaCentaur.Repo.DataMigrations.TrackingIsTwoSwitches do
  @moduledoc """
  Spec 2026-09-14 (UIDR-042): the ladder loses its `ask` and `default`
  rungs. A per-title grab policy no longer exists — Grab plans the
  release, and the person's planning mode says whether the plan asks
  first — so `ask` becomes `grab`. `default` followed the global
  auto-grab setting, which is deleted here too: a title at `default`
  becomes `grab`, unless that setting was Notify only (`"off"`), in which
  case the title only ever kept a calendar and becomes `follow`.

  This file is **append-only**. Never edit a shipped data migration.

  Raw SQL, snapshot-style: no live schema aliases. Idempotent — a second
  run finds no `ask` or `default` rows and no setting to delete.
  """
  use Ecto.Migration

  @setting_key "auto_grab.default_mode"
  @notify_only "off"

  def up, do: sweep(repo())

  # `grab` and `follow` were legal rungs before this migration, and an
  # absent setting reads as the old built-in default (Grab it).
  def down, do: :ok

  @doc "Folds the retired rungs and deletes the retired setting. Returns `:ok`."
  def sweep(repo) do
    default_rung =
      case repo.query!(
             "SELECT json_extract(value, '$.value') FROM settings_entries WHERE key = ?",
             [@setting_key]
           ) do
        %{rows: [[@notify_only]]} -> "follow"
        _grab_ask_or_absent -> "grab"
      end

    repo.query!("UPDATE title_intents SET rung = 'grab' WHERE rung = 'ask'", [])
    repo.query!("UPDATE title_intents SET rung = ? WHERE rung = 'default'", [default_rung])
    repo.query!("DELETE FROM settings_entries WHERE key = ?", [@setting_key])
    :ok
  end
end
```

- [ ] **Step 4: Run the test**

Run: `~/scripts/agents/agent-mix test test/media_centaur/repo/data_migrations/tracking_is_two_switches_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add priv/repo/data_migrations/20260914120000_tracking_is_two_switches.exs test/media_centaur/repo/data_migrations/tracking_is_two_switches_test.exs
git commit -m "feat(migrations): fold the ask and default rungs; delete the auto-grab default mode"
```

---

### Task 5: Acquisition reads `grabs?` and the planning mode

**Files:**
- Modify: `lib/media_centaur/acquisition/drop_planner.ex:172-190, 228, 271, 321-329`
- Modify: `lib/media_centaur/acquisition/mode_reconciler.ex:1-40, 126-134`
- Modify: `lib/media_centaur/acquisition/reactor/handlers.ex:92-101`
- Modify: `lib/media_centaur/acquisition/targeting.ex:219-236`
- Test: `test/media_centaur/acquisition/drop_planner_test.exs:266-300, 413-434`

- [ ] **Step 1: Rewrite the mode tests**

In `test/media_centaur/acquisition/drop_planner_test.exs`, replace the two tests "ask mode leaves the solved plan ready…" and "off mode plans nothing" with:

```elixir
    test "under manual planning the solved plan parks ready, and a second tick does not duplicate it" do
      stub_results(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{seeders: 30})
        ]
      })

      MediaCentaur.Settings.Preferences.PlanningMode.set(:manually_select_release)
      item = create_tracked_show()
      create_intent_for(item, :grab)
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()

      assert [] = Repo.all(Pursuit)
      [plan] = Plans.list_drafts()
      assert plan.status == "ready"
      assert plan.origin == "tracking"
      assert plan.approval_policy == "review"

      tick_and_gate()

      assert [_still_just_one] = Plans.list_drafts()
    end

    test "a title at Follow plans nothing" do
      item = create_tracked_show()
      create_intent_for(item, :follow)
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()

      assert Repo.all(Plans.Plan) == []
```

(keep the rest of the former "off mode" test body as it was after that line.)

Replace the test "an item inheriting a global default of off is reconciled too" with:

```elixir
    test "turning auto-grab off reconciles the parked draft on the next sweep" do
      episode_stub()

      MediaCentaur.Settings.Preferences.PlanningMode.set(:manually_select_release)
      item = create_tracked_show()
      create_intent_for(item, :grab)
      create_aired_release(item, 1, 1, @last_month)
      :ok = ReleaseTracking.sync_wants(item)

      tick_and_gate()
      assert [_parked] = Plans.list_drafts()

      create_intent_for(item, :follow)

      Handlers.tracking_sweep_completed()

      assert Plans.list_drafts() == []
    end
```

Search the same file for every other `create_intent_for(item, :ask)` and `create_intent_for(item, :default)` and change them to `:grab`; where a test's intent is "ask first", add `MediaCentaur.Settings.Preferences.PlanningMode.set(:manually_select_release)` at its top. The "auto mode end-to-end" describe relies on the auto policy: add `MediaCentaur.Settings.Preferences.PlanningMode.set(:auto_select_best_release)` to the module `setup` block (the built-in default is manual).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/drop_planner_test.exs`
Expected: FAIL — the planner still calls `Discovery.grab_mode/3`, which no longer exists (compile error in the acquisition modules).

- [ ] **Step 3: Change the four readers**

`lib/media_centaur/acquisition/drop_planner.ex`:

Add `alias MediaCentaur.Settings.Preferences.PlanningMode` to the aliases.

Replace `plan_item/4`:

```elixir
  defp plan_item(item_id, wants, settings, now) do
    with %Item{} = item <- ReleaseTracking.get_item(item_id),
         true <- Discovery.grabs?(item.tmdb_id, item.media_type) do
      due = Enum.filter(wants, &WantSchedule.due?(&1, now))

      case item.media_type do
        :tv_series ->
          plan_tv_drop(item, due, settings, now)

        :movie ->
          Enum.each(due, &plan_movie_drop(item, &1, settings, now))
      end
    end

    :ok
  end
```

Replace the `approval_policy/2` comment and function with:

```elixir
  # Who commits the plan is the person's planning mode — the same answer
  # the Download button gives (spec 2026-09-14): manual select parks it
  # for review, auto-select lets the gate commit. Titles that do not grab
  # never reach here (`plan_item/4` guards it).
  defp approval_policy, do: PlanningMode.approval_policy(PlanningMode.value())
```

At lines 228 and 271 change `approval_policy: approval_policy(item, settings),` to `approval_policy: approval_policy(),`. Update the moduledoc sentence "reading the stamped `approval_policy`" context if it names the auto-grab mode; the glossary's Approval policy entry is updated in Task 15.

`lib/media_centaur/acquisition/mode_reconciler.ex`:

In `off?/3` replace the inner `item -> Discovery.grab_mode(...) == "off"` with `item -> not Discovery.grabs?(item.tmdb_id, item.media_type)`. In the moduledoc, change "when an item's *effective* auto-grab mode is `off` — flipped per-item or inherited from a global default change —" to "when a title no longer grabs (`Discovery.grabs?/2` is false — its rung dropped below Grab) —", and "sees per-item flips, global-default flips, and restarts identically" to "sees rung drops and restarts identically". Drop any now-unused alias.

`lib/media_centaur/acquisition/reactor/handlers.ex`: in `tracking_item_off?/1` replace the `item ->` clause body with `not Discovery.grabs?(item.tmdb_id, item.media_type)`. Remove the `AutoGrabSettings` alias if nothing else in the file uses it.

`lib/media_centaur/acquisition/targeting.ex`: in `tracked_want_units/1` replace the `mode when mode != "off" <- MediaCentaur.Discovery.grab_mode(...)` clause with `true <- MediaCentaur.Discovery.grabs?(item.tmdb_id, item.media_type)`, and the comment "or when the effective auto-grab mode is off" with "or when the title does not grab".

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/drop_planner_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition test/media_centaur/acquisition/drop_planner_test.exs
git commit -m "refactor(acquisition): a title grabs or it does not; the planning mode stamps tracking plans"
```

---

### Task 6: The forecast reads the approval policy

The feed predicts what the drop planner will stamp, so its context carries the planner's word — `approval_policy`, `"automatic"` or `"review"` — not the Settings atom. The host maps the setting once with `PlanningMode.approval_policy/1`.

**Files:**
- Modify: `lib/media_centaur/release_tracking/upcoming_feed.ex:15-17, 37-40, 286-296`
- Modify: `lib/media_centaur_web/components/release_tracking/tracking_detail.ex`
- Modify: `lib/media_centaur_web/live/incoming_live/view.ex:62, 106`
- Modify: `lib/media_centaur_web/live/incoming_live.ex:221, 393-419`
- Modify: `lib/media_centaur_web/live/entity_modal.ex:1994-2001`
- Test: `test/media_centaur/release_tracking/upcoming_feed_test.exs:17-31, 333-358`
- Test: `test/media_centaur_web/live/incoming_live/view_test.exs:42-58`

- [ ] **Step 1: Rewrite the failing tests**

In `test/media_centaur/release_tracking/upcoming_feed_test.exs` replace `armed_context/1` and its comment with:

```elixir
  # A context where acquisition is live and tracking plans commit by
  # themselves — the "trusting automation" posture. Every title in it
  # sits at Grab unless a test says otherwise.
  defp armed_context(overrides \\ %{}) do
    Map.merge(
      %{
        today: @today,
        acquisition_ready?: true,
        approval_policy: "automatic",
        rungs: %{{1001, :tv_series} => :grab, {2002, :movie} => :grab},
        grab_status_by_key: %{}
      },
      overrides
    )
  end
```

Replace the three tests `global default "off" + a title at Default`, `a title at Default inherits an "all_releases" default` and `Ask is not full-auto` with:

```elixir
    test "a review policy parks the drop for a person → neutral :upcoming" do
      item = tv_item()
      episode = release(item, %{title: "ep", air_date: days(3), season_number: 1, episode_number: 1})

      feed = UpcomingFeed.build([episode], armed_context(%{approval_policy: "review"}))

      assert find_event(feed, "ep").status == :upcoming
    end

    test "a title at Grab under an automatic policy → :armed" do
      item = tv_item()
      episode = release(item, %{title: "ep", air_date: days(3), season_number: 1, episode_number: 1})

      feed = UpcomingFeed.build([episode], armed_context(at_rung(item, :grab)))

      assert find_event(feed, "ep").status == :armed
    end
```

Update the module doc's "the global auto-grab default" to "the approval policy tracking plans are stamped with". Search the file for any remaining `:default` or `:ask` rung and change it to `:grab`.

In `test/media_centaur_web/live/incoming_live/view_test.exs` `inputs/1`: replace `auto_grab_default_mode: "all_releases",` with `approval_policy: "automatic",`, the comment with `# Every fixture title sits at Grab, so the policy above is what decides whether a release reads as armed.`, and the rungs map with `rungs: %{{1001, :tv_series} => :grab, {2002, :movie} => :grab},`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/release_tracking/upcoming_feed_test.exs test/media_centaur_web/live/incoming_live/view_test.exs`
Expected: FAIL — `will_auto_grab?` reads `context.auto_grab_default_mode` (KeyError).

- [ ] **Step 3: Change the context key**

`lib/media_centaur/release_tracking/upcoming_feed.ex`:

Moduledoc bullet:

```
    * `:approval_policy` — what the drop planner will stamp a tracking
      plan with: `"automatic"` (the gate commits it) or `"review"` (a
      person does). `PlanningMode.approval_policy/1` of the person's
      planning mode, mapped by the caller. Only `"automatic"` arms.
```

Status doc for `:armed`: "(only when acquisition is ready AND the title's rung is Grab AND the approval policy is automatic)".

Replace `will_auto_grab?/2`:

```elixir
  # Honest "armed": a grab only fires when acquisition is live, the title
  # grabs, and the plan the drop makes commits without a person. Pure:
  # the rung and the policy come in on the context, keyed by title.
  defp will_auto_grab?(item, context) do
    rung = Map.get(context[:rungs] || %{}, {item.tmdb_id, item.media_type})

    context.acquisition_ready? and TitleIntent.grabs?(rung) and
      context.approval_policy == "automatic"
  end
```

`lib/media_centaur_web/components/release_tracking/tracking_detail.ex`:

- Remove `default_grab_mode: "off",` from `defstruct` and `default_grab_mode: String.t(),` from `@type t`.
- Change the `context` typedoc and type to `approval_policy: String.t()`, doc: "`approval_policy` — `PlanningMode.approval_policy/1` of the person's planning mode".
- In `build/2`: `approval_policy: context.approval_policy,` in the `UpcomingFeed.build` map; delete `default_grab_mode: context.auto_grab_default_mode,` from the struct.
- Moduledoc: replace "`acquisition?`, `default_grab_mode`" with "`acquisition?`" and "(`ReleaseTimeline`, `TrackingModeControl`)" with "(`ReleaseTimeline`, `TrackingControls`)".

`lib/media_centaur_web/live/incoming_live/view.ex`: line 62 doc key `:approval_policy`; line 106 `approval_policy: inputs.approval_policy,`.

`lib/media_centaur_web/live/incoming_live.ex`: add `alias MediaCentaur.Settings.Preferences.PlanningMode`; line 221 `approval_policy: PlanningMode.approval_policy(PlanningMode.value()),`; in `build_view/1` replace `default_mode = AutoGrabSettings.load().default_mode` with `approval_policy = PlanningMode.approval_policy(PlanningMode.value())`, the input `auto_grab_default_mode: default_mode,` with `approval_policy: approval_policy,`, and the assign `auto_grab_default_mode: default_mode` with `approval_policy: approval_policy`. Remove the `AutoGrabSettings` alias if unused (line 892 is removed in Task 11).

`lib/media_centaur_web/live/entity_modal.ex` `load_tracking/1`: `approval_policy: PlanningMode.approval_policy(PlanningMode.value())` in place of `auto_grab_default_mode: AutoGrabSettings.load().default_mode`.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/release_tracking/upcoming_feed_test.exs test/media_centaur_web/live/incoming_live/view_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/release_tracking/upcoming_feed.ex lib/media_centaur_web/components/release_tracking/tracking_detail.ex lib/media_centaur_web/live/incoming_live/view.ex lib/media_centaur_web/live/incoming_live.ex lib/media_centaur_web/live/entity_modal.ex test/media_centaur/release_tracking/upcoming_feed_test.exs test/media_centaur_web/live/incoming_live/view_test.exs
git commit -m "refactor(release-tracking): the forecast arms on Grab under an automatic approval policy"
```

---

### Task 7: `Title.Logic` — release ahead, markers, detail

**Files:**
- Modify: `lib/media_centaur_web/components/title/logic.ex`
- Modify: `lib/media_centaur_web/components/title/detail.ex`
- Test: `test/media_centaur_web/components/title/logic_test.exs:134-170`

- [ ] **Step 1: Rewrite the failing tests**

Replace `describe "row_markers/2 tracking"` in `test/media_centaur_web/components/title/logic_test.exs` with:

```elixir
  describe "row_markers/2 tracking" do
    test "a followed title says Tracking, a grabbing one Auto-grab; Off and owned say nothing" do
      base = %{in_library?: false, acquisition_state: nil, rung: nil}

      assert Logic.row_markers(%{base | rung: :follow}) == ["Tracking"]
      assert Logic.row_markers(%{base | rung: :grab}) == ["Auto-grab"]
      assert Logic.row_markers(%{base | rung: :list}) == ["On your list"]
      assert Logic.row_markers(base) == []
      assert Logic.row_markers(%{base | in_library?: true, rung: :grab}) == ["In library"]
    end

    test "an ignored title says so — a search result you dismissed is still findable" do
      base = %{in_library?: false, acquisition_state: nil}
      assert Logic.row_markers(Map.put(base, :rung, :ignored)) == ["Ignored"]
      assert Logic.row_markers(Map.put(base, :rung, :ignored), true) == ["Ignored"]
    end

    test "list_implied? drops only the List marker" do
      base = %{in_library?: false, acquisition_state: nil, rung: nil}

      assert Logic.row_markers(Map.put(base, :rung, :list), true) == []
      assert Logic.row_markers(Map.put(base, :rung, :follow), true) == ["Tracking"]
    end
  end

  describe "release_ahead?/3 — whether the Track release dates row has anything to track" do
    alias MediaCentaur.TMDB.ReleaseWindow

    @today ~D[2026-09-14]

    defp movie(release_date), do: Title.new!(%{tmdb_id: 1, media_type: :movie, name: "Movie A", release_date: release_date})

    test "a series always has a release ahead as far as the snapshot knows" do
      show = Title.new!(%{tmdb_id: 2, media_type: :tv_series, name: "Sample Show"})
      assert Logic.release_ahead?(show, nil, @today)
    end

    test "without the window, the snapshot's primary date decides" do
      assert Logic.release_ahead?(movie(~D[2026-12-01]), nil, @today)
      assert Logic.release_ahead?(movie(nil), nil, @today)
      refute Logic.release_ahead?(movie(~D[2020-01-01]), nil, @today)
    end

    test "with the window, only a home release that has passed says no" do
      out = movie(~D[2020-01-01])
      assert Logic.release_ahead?(out, %ReleaseWindow{stage: :unreleased}, @today)
      assert Logic.release_ahead?(out, %ReleaseWindow{stage: :theatrical}, @today)
      refute Logic.release_ahead?(movie(~D[2026-12-01]), %ReleaseWindow{stage: :home}, @today)
    end

    test "an unknown window defers to the snapshot" do
      assert Logic.release_ahead?(movie(~D[2026-12-01]), %ReleaseWindow{stage: :unknown}, @today)
      refute Logic.release_ahead?(movie(~D[2020-01-01]), %ReleaseWindow{stage: :unknown}, @today)
    end
  end
```

Also in the `title_detail/2` describe, add:

```elixir
    test "carries the release window (nil until the preview lands) and whether the title is complete" do
      detail = Logic.title_detail(released(), facts())
      assert detail.release_window == nil
      refute detail.complete?

      window = %ReleaseWindow{stage: :theatrical}
      detail = Logic.title_detail(released(), Map.merge(facts(), %{release_window: window, complete?: true}))
      assert detail.release_window == window
      assert detail.complete?
    end
```

(`released/0` and `facts/0` are that describe's existing helpers; use whatever the file names them.) Make sure the file aliases `MediaCentaur.TMDB.Title` and `MediaCentaur.TMDB.ReleaseWindow` at the top.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/logic_test.exs`
Expected: FAIL — old marker words; `release_ahead?/3` undefined; the detail has no `release_ahead?` key.

- [ ] **Step 3: Change the logic and the detail**

`lib/media_centaur_web/components/title/detail.ex`:

- In `defstruct`, remove `default_grab_mode: "off",` and add `:release_window,` (among the nil-default keys) and `complete?: false,`.
- In `@type t`, remove `default_grab_mode: String.t(),` and add `release_window: ReleaseWindow.t() | nil,` and `complete?: boolean(),` (alias `MediaCentaur.TMDB.ReleaseWindow`).
- Moduledoc: delete the two sentences mentioning `default_grab_mode`; replace "`acquisition?` and `default_grab_mode` are what the tracking-mode control needs to say honestly what each mode does right now." with:

```
  `acquisition?`, `planning_mode`, `complete?` and `release_window` are
  what the tracking controls need: whether a grab can fire, whether it
  asks first, whether the library already owns the film
  (`ReleaseTracking.complete?/2`), and where a movie stands in its
  release sequence — nil until the live preview lands, and for a series.
  The rows derive their rule from these at the mount
  (`Logic.release_ahead?/3`); the detail carries facts, not the rule.
```

`lib/media_centaur_web/components/title/logic.ex`:

- Add `alias MediaCentaur.TMDB.ReleaseWindow`.
- In `title_detail/2`: replace `default_grab_mode: Map.get(facts, :default_grab_mode, "off"),` with `release_window: Map.get(facts, :release_window),` and `complete?: Map.get(facts, :complete?, false),`; in its doc, replace `default_grab_mode` with `release_window`, `complete?`.
- Add after `title_detail/2`:

```elixir
  @doc """
  Whether a release is still ahead — what decides if the Track release
  dates row renders (`TrackingControls.rows/1`). A series always has one
  ahead as far as the snapshot knows. For a movie the release window
  read from the live TMDB payload answers once it has landed
  (`:unreleased` and `:theatrical` are ahead, `:home` is not, `:unknown`
  says nothing and defers to the snapshot); until then the snapshot's
  primary date against `today` (`MediaResults.release_status/2`).
  """
  @spec release_ahead?(Title.t(), ReleaseWindow.t() | nil, Date.t()) :: boolean()
  def release_ahead?(%Title{media_type: :tv_series}, _window, _today), do: true

  def release_ahead?(%Title{media_type: :movie} = title, %ReleaseWindow{stage: :unknown}, today),
    do: release_ahead?(title, nil, today)

  def release_ahead?(%Title{media_type: :movie}, %ReleaseWindow{stage: stage}, _today),
    do: stage in [:unreleased, :theatrical]

  def release_ahead?(%Title{media_type: :movie} = title, nil, today),
    do: MediaResults.release_status(title, today) == :upcoming
```

- In `row_markers/2`: remove `optional(:default_grab_mode) => String.t(),` from the spec; change the call to `rung_marker(Map.get(facts, :rung), list_implied?)`; in its doc replace "then the tracking rung (`rung` + `default_grab_mode`, Default resolved to what it does; never for an owned title, whose tracking is the library detail's)" with "then the tracking rung (Tracking at Follow, Auto-grab at Grab; never for an owned title, whose tracking is the library detail's)".
- Replace the `rung_marker` clauses and their comment with:

```elixir
  # Off says nothing — the row would not be here. Ignored says so: the
  # Feed hides it, but a search result must still say the reader
  # dismissed it. List says it is on the list, except where the
  # container already says so.
  defp rung_marker(nil, _list_implied?), do: nil
  defp rung_marker(:ignored, _list_implied?), do: "Ignored"
  defp rung_marker(:list, true), do: nil
  defp rung_marker(:list, false), do: "On your list"
  defp rung_marker(:follow, _list_implied?), do: "Tracking"
  defp rung_marker(:grab, _list_implied?), do: "Auto-grab"
```

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/logic_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/title/logic.ex lib/media_centaur_web/components/title/detail.ex test/media_centaur_web/components/title/logic_test.exs
git commit -m "feat(title): the detail carries the release window and completeness; Tracking / Auto-grab markers"
```

---

### Task 8: `settings_row/1` gains `id` and `disabled?`

**Files:**
- Modify: `lib/media_centaur_web/components/settings.ex:19-46`
- Modify: `storybook/settings/settings_row.story.exs`

- [ ] **Step 1: Add the story variation (the acceptance criterion)**

Append to `variations/0` in `storybook/settings/settings_row.story.exs`:

```elixir
      %Variation{
        id: :disabled,
        description:
          "No click, `aria-disabled`, and the description says why — the row stays in " <>
            "the nav graph. The title view's Track release dates row while auto-grab is on.",
        attributes: %{
          id: "settings-row-disabled",
          label: "Track release dates",
          description: "Stays on while auto-grab is on.",
          checked: true,
          disabled?: true,
          event: "set_rung"
        }
      }
```

- [ ] **Step 2: Extend the component**

In `lib/media_centaur_web/components/settings.ex`, before `settings_row/1`'s `attr :label`, add:

```elixir
  attr :id, :string, default: nil

  attr :disabled?, :boolean,
    default: false,
    doc:
      "no click and `aria-disabled`; the description says why. The row keeps its place so the nav graph never shifts."
```

Replace the row's root element:

```elixir
    <div
      id={@id}
      class={[
        "flex items-center justify-between py-2.5 px-3.5 gap-4 rounded-lg transition-colors duration-150",
        if(@disabled?,
          do: "opacity-60",
          else: "cursor-pointer hover:bg-base-content/[0.04]"
        )
      ]}
      data-nav-item
      tabindex="0"
      aria-disabled={@disabled? && "true"}
      phx-click={!@disabled? && @event}
      {phx_values(if(@disabled?, do: %{}, else: @event_value))}
    >
```

- [ ] **Step 3: Render the story**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_render_test.exs`
Expected: PASS (the new variation renders).

- [ ] **Step 4: Commit**

```bash
git add lib/media_centaur_web/components/settings.ex storybook/settings/settings_row.story.exs
git commit -m "feat(settings-kit): settings_row takes an id and a disabled state"
```

---

### Task 9: `TrackingControls` replaces `IntentControl`

**Files:**
- Create: `lib/media_centaur_web/components/title/tracking_controls.ex`
- Create: `storybook/title/tracking_controls.story.exs`
- Create: `test/media_centaur_web/components/title/tracking_controls_test.exs`
- Delete: `lib/media_centaur_web/components/title/intent_control.ex`, `storybook/title/intent_control.story.exs`, `test/media_centaur_web/components/title/intent_control_test.exs`
- Modify: `storybook/title/_title.index.exs`

- [ ] **Step 1: Write the failing test**

`test/media_centaur_web/components/title/tracking_controls_test.exs`:

```elixir
defmodule MediaCentaurWeb.Components.Title.TrackingControlsTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaurWeb.Components.Title.TrackingControls

  defp attrs(overrides) do
    Map.merge(
      %{
        id: "tc",
        ref: "movie-1",
        rung: :list,
        media_type: :movie,
        release_ahead?: true,
        complete?: false,
        approval_policy: "review",
        acquisition?: true
      },
      overrides
    )
  end

  defp render(overrides), do: render_component(&TrackingControls.tracking_controls/1, attrs(overrides))

  describe "control_form/1 — which form the block takes (UIDR-039)" do
    test "no record: nothing — listing is the bookmark's act" do
      assert TrackingControls.control_form(nil) == :none
    end

    test "ignored: the one line" do
      assert TrackingControls.control_form(:ignored) == :ignored
    end

    test "listed: the rows" do
      for rung <- [:list, :follow, :grab], do: assert(TrackingControls.control_form(rung) == :controls)
    end
  end

  describe "rows/1 — which rows a listed title gets" do
    test "a movie the library owns is complete: no rows" do
      assert TrackingControls.rows(%{media_type: :movie, release_ahead?: true, complete?: true}) == []
    end

    test "a movie that is out offers only Auto-grab — nothing left to track" do
      assert TrackingControls.rows(%{media_type: :movie, release_ahead?: false, complete?: false}) == [:grab]
    end

    test "a movie with a release ahead, and any series, offer both" do
      assert TrackingControls.rows(%{media_type: :movie, release_ahead?: true, complete?: false}) == [:track, :grab]
      assert TrackingControls.rows(%{media_type: :tv_series, release_ahead?: true, complete?: false}) == [:track, :grab]
    end
  end

  describe "the rung each row sets" do
    test "Track: Follow when off, List when on, nothing while auto-grab holds it on" do
      assert TrackingControls.track_choice(:list) == "follow"
      assert TrackingControls.track_choice(:follow) == "list"
      assert TrackingControls.track_choice(:grab) == nil
    end

    test "Auto-grab: Grab when off; when on, back to Follow, or to List when there is no Track row" do
      assert TrackingControls.grab_choice(:list, [:track, :grab]) == "grab"
      assert TrackingControls.grab_choice(:follow, [:track, :grab]) == "grab"
      assert TrackingControls.grab_choice(:grab, [:track, :grab]) == "follow"
      assert TrackingControls.grab_choice(:grab, [:grab]) == "list"
    end
  end

  describe "rendering" do
    test "a listed movie with a release ahead: both rows, both off, each carrying its choice and the ref" do
      html = render(%{})

      assert html =~ ~s(id="tc-track")
      assert html =~ ~s(phx-value-choice="follow")
      assert html =~ ~s(id="tc-grab")
      assert html =~ ~s(phx-value-choice="grab")
      assert html =~ ~s(phx-value-ref="movie-1")
      refute html =~ "aria-disabled"
    end

    test "at Grab the Track row is on and disabled, and says why" do
      html = render(%{rung: :grab})

      assert html =~ ~s(id="tc-track")
      assert html =~ ~s(aria-disabled="true")
      assert html =~ "Stays on while auto-grab is on."
      assert html =~ ~s(phx-value-choice="follow")
    end

    test "a movie that is out shows Auto-grab only" do
      html = render(%{release_ahead?: false})
      refute html =~ ~s(id="tc-track")
      assert html =~ ~s(id="tc-grab")
    end

    test "a complete movie shows no rows" do
      html = render(%{complete?: true})
      refute html =~ ~s(id="tc-track")
      refute html =~ ~s(id="tc-grab")
      assert html =~ ~s(data-form="controls")
    end

    test "the Auto-grab description follows the approval policy and the media type" do
      assert render(%{}) =~ "a plan waits for your approval on Incoming"
      assert render(%{approval_policy: "automatic"}) =~ "downloads when it drops, without asking"
      assert render(%{media_type: :tv_series}) =~ "New and missing episodes are planned"
      assert render(%{media_type: :tv_series, approval_policy: "automatic"}) =~ "New and missing episodes download without asking"
    end

    test "without acquisition the note says auto-grab downloads nothing" do
      assert render(%{acquisition?: false}) =~ "downloads nothing until an indexer and a download client"
      refute render(%{}) =~ "downloads nothing until"
    end

    test "an ignored title shows the one line; a title with no record shows nothing" do
      assert render(%{rung: :ignored}) =~ "Hidden from the Feed"
      refute render(%{rung: :ignored}) =~ ~s(id="tc-track")

      html = render(%{rung: nil})
      assert html =~ ~s(data-form="none")
      refute html =~ ~s(id="tc-track")
      refute html =~ "Hidden from the Feed"
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/tracking_controls_test.exs`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the component**

`lib/media_centaur_web/components/title/tracking_controls.ex`:

```elixir
defmodule MediaCentaurWeb.Components.Title.TrackingControls do
  @moduledoc """
  What a listed title shows beneath its details (spec 2026-09-14,
  UIDR-042): up to two switch rows over the one record,
  `Discovery.TitleIntent`.

  * **Track release dates** — on at Follow and above. The app keeps the
    title's calendar; its dates show under Coming up on Incoming.
    Rendered only while a release is ahead (`release_ahead?`): an
    unreleased movie, or any series.
  * **Auto-grab** — on at Grab. When a release drops the app plans it;
    whether the plan commits by itself or waits for approval is the
    approval policy the person's planning mode maps to
    (`Settings.Preferences.PlanningMode.approval_policy/1`), the same
    answer the Download button gives — the host maps it once and passes
    the policy. Auto-grab implies the calendar, so while it is on the
    Track row stays on and takes no click. A movie the library already
    owns is complete (`complete?`, `ReleaseTracking.complete?/2`) and
    gets no rows at all.

  The bookmark in the action strip (`WatchlistToggle`) is the first act:
  a title with no record shows nothing here (UIDR-039), and an ignored
  title shows the one line saying the Feed hides it. `control_form/1` is
  that rule; `rows/1` decides which rows a listed title gets.

  A click pushes `set_rung` with `phx-value-choice` — the rung the row
  sets (`track_choice/1`, `grab_choice/2`), never a toggle the host has
  to interpret — and `phx-value-ref`. The rows are the Settings kit's
  toggle row (`Settings.settings_row/1`): a labelled switch that saves
  on the act is one idiom, wherever it sits. The host places the block
  above everything tracking produces (the timeline, the activity), so
  flipping a switch never moves it. A list row never wears the rows — it
  shows its rung as a quiet marker and opens its modal to change it.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.Settings, only: [settings_row: 1]

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.TMDB.Title

  @mode_pointer "Change this under Settings → Acquisition → Download button."

  attr :id, :string, required: true

  attr :ref, :string,
    required: true,
    doc: "the title's `MediaCentaurWeb.TitleRef.param/1`, carried on every click"

  attr :rung, :atom,
    values: [nil, :ignored, :list, :follow, :grab],
    default: nil,
    doc: "the rung the title's intent sits at; nil means the title is Off — no record"

  attr :media_type, :atom, values: [:movie, :tv_series], required: true

  attr :release_ahead?, :boolean,
    required: true,
    doc:
      "a release is still to come (`Title.Logic.release_ahead?/3`); the Track row renders only then. Always true for a series."

  attr :complete?, :boolean,
    required: true,
    doc: "nothing left to release — a movie the library owns. No rows."

  attr :approval_policy, :string,
    values: ["automatic", "review"],
    required: true,
    doc:
      "what a tracking plan is stamped with — `PlanningMode.approval_policy/1` of the person's planning mode; whether an auto-grab asks first"

  attr :acquisition?, :boolean,
    required: true,
    doc: "an indexer and a download client are ready; without them auto-grab downloads nothing"

  def tracking_controls(assigns) do
    rows = rows(assigns)
    assigns = assign(assigns, form: control_form(assigns.rung), rows: rows)

    ~H"""
    <div
      id={@id}
      class="space-y-2"
      data-component="tracking-controls"
      data-rung={@rung || :off}
      data-form={@form}
    >
      <p :if={@form == :ignored} class="text-sm text-base-content/70">{ignored_line()}</p>
      <div :if={@form == :controls} class="space-y-0.5">
        <.settings_row
          :if={:track in @rows}
          id={"#{@id}-track"}
          label="Track release dates"
          description={track_description(@media_type, @rung)}
          checked={TitleIntent.follows_releases?(@rung)}
          disabled?={is_nil(track_choice(@rung))}
          event="set_rung"
          event_value={%{"choice" => track_choice(@rung), "ref" => @ref}}
        />
        <.settings_row
          :if={:grab in @rows}
          id={"#{@id}-grab"}
          label="Auto-grab"
          description={grab_description(@media_type, @approval_policy)}
          checked={TitleIntent.grabs?(@rung)}
          event="set_rung"
          event_value={%{"choice" => grab_choice(@rung, @rows), "ref" => @ref}}
        />
      </div>
      <p
        :if={@form == :controls and :grab in @rows and !@acquisition?}
        id={"#{@id}-acquisition-note"}
        class="text-xs text-base-content/55 px-3.5"
      >
        Auto-grab downloads nothing until an indexer and a download client are set up under Settings → Acquisition.
      </p>
    </div>
    """
  end

  @doc """
  Which form the block takes (UIDR-039): `:none` for a title with no
  record — the bookmark in the action strip is its verb; `:ignored` — the
  one line saying the Feed hides it; `:controls` — the rows — for a title
  on the list.
  """
  @spec control_form(TitleIntent.rung() | nil) :: :none | :ignored | :controls
  def control_form(nil), do: :none
  def control_form(:ignored), do: :ignored
  def control_form(_listed), do: :controls

  @doc """
  Which rows a listed title gets. A movie the library owns is complete:
  none. A movie that is out has nothing left to track: Auto-grab only —
  which keeps searching until a release exists, unlike the Download
  button. A movie with a release ahead, and any series: both.
  """
  @spec rows(%{
          required(:media_type) => Title.media_type(),
          required(:release_ahead?) => boolean(),
          required(:complete?) => boolean(),
          optional(atom()) => term()
        }) :: [:track | :grab]
  def rows(%{complete?: true}), do: []
  def rows(%{media_type: :movie, release_ahead?: false}), do: [:grab]
  def rows(_movie_ahead_or_series), do: [:track, :grab]

  @doc "What the Track row sets: Follow from List, List from Follow; nothing at Grab, which holds it on."
  @spec track_choice(TitleIntent.rung()) :: String.t() | nil
  def track_choice(:list), do: "follow"
  def track_choice(:follow), do: "list"
  def track_choice(:grab), do: nil

  @doc """
  What the Auto-grab row sets: Grab from below; from Grab, back to Follow
  when the Track row is there to show it, else List — turning off the only
  switch shown leaves the title plainly listed.
  """
  @spec grab_choice(TitleIntent.rung(), [:track | :grab]) :: String.t()
  def grab_choice(:grab, rows), do: if(:track in rows, do: "follow", else: "list")
  def grab_choice(_below_grab, _rows), do: "grab"

  @doc "The Track row's one line: what shows on Coming up, or that auto-grab holds the row on."
  @spec track_description(Title.media_type(), TitleIntent.rung()) :: String.t()
  def track_description(_media_type, :grab), do: "Stays on while auto-grab is on."

  def track_description(:movie, _rung),
    do: "Theatrical, digital and disc dates show under Coming up on Incoming."

  def track_description(:tv_series, _rung), do: "Upcoming episodes show under Coming up on Incoming."

  @doc "The Auto-grab row's line: what a drop does under the approval policy, and where that is set."
  @spec grab_description(Title.media_type(), String.t()) :: String.t()
  def grab_description(:movie, "automatic"),
    do: "The release downloads when it drops, without asking. " <> @mode_pointer

  def grab_description(:movie, "review"),
    do: "When the release drops, a plan waits for your approval on Incoming. " <> @mode_pointer

  def grab_description(:tv_series, "automatic"),
    do: "New and missing episodes download without asking. " <> @mode_pointer

  def grab_description(:tv_series, "review"),
    do: "New and missing episodes are planned and wait for your approval on Incoming. " <> @mode_pointer

  @doc "The line an ignored title shows in place of the rows."
  @spec ignored_line() :: String.t()
  def ignored_line, do: "Hidden from the Feed. Add it to your watchlist to bring it back."
end
```

- [ ] **Step 4: Write the story**

`storybook/title/tracking_controls.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Title.TrackingControls do
  @moduledoc """
  The rows a listed title shows beneath its details (UIDR-042): Track
  release dates and Auto-grab, over the one record. A title not on the
  list shows nothing — the bookmark in the action strip lists it; an
  ignored one shows the line saying the Feed hides it. Auto-grab holds
  the Track row on; a movie that is out has only Auto-grab; a movie the
  library owns has no rows.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Title.TrackingControls.tracking_controls/1

  defp base(overrides) do
    Map.merge(
      %{
        id: "tracking-controls-story",
        ref: "tv_series-1399",
        rung: :list,
        media_type: :tv_series,
        release_ahead?: true,
        complete?: false,
        approval_policy: "review",
        acquisition?: true
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :not_listed,
        description: "A title with no record: nothing — listing is the bookmark's act (UIDR-039).",
        attributes: base(%{rung: nil})
      },
      %Variation{
        id: :ignored,
        description: "An ignored title shows the one line that says the Feed is hiding it.",
        attributes: base(%{rung: :ignored})
      },
      %VariationGroup{
        id: :series_by_rung,
        description: "A listed series at each rung: both rows; at Grab the Track row is held on.",
        variations:
          for rung <- [:list, :follow, :grab] do
            %Variation{id: rung, attributes: base(%{rung: rung})}
          end
      },
      %VariationGroup{
        id: :movie_by_rung,
        description: "A listed movie with a release ahead, at each rung.",
        variations:
          for rung <- [:list, :follow, :grab] do
            %Variation{id: rung, attributes: base(%{rung: rung, media_type: :movie, ref: "movie-550"})}
          end
      },
      %Variation{
        id: :movie_out,
        description: "A movie that is out: nothing left to track, so Auto-grab alone — it keeps searching until a release exists.",
        attributes: base(%{media_type: :movie, ref: "movie-550", release_ahead?: false})
      },
      %Variation{
        id: :movie_in_library,
        description: "A movie the library owns is complete: no rows.",
        attributes: base(%{media_type: :movie, ref: "movie-550", complete?: true})
      },
      %Variation{
        id: :automatic,
        description: "Under an automatic approval policy (auto-select planning) the Auto-grab line says it downloads without asking.",
        attributes: base(%{rung: :grab, approval_policy: "automatic"})
      },
      %Variation{
        id: :acquisition_missing,
        description: "No indexer or download client yet: the rows stay, and the note says auto-grab downloads nothing until one is set up.",
        attributes: base(%{rung: :grab, acquisition?: false})
      }
    ]
  end
end
```

In `storybook/title/_title.index.exs` replace the `intent_control` entry with:

```elixir
  def entry("tracking_controls"), do: [icon: {:fa, "sliders", :thin}, name: "Tracking controls"]
```

Delete `lib/media_centaur_web/components/title/intent_control.ex`, `storybook/title/intent_control.story.exs` and `test/media_centaur_web/components/title/intent_control_test.exs`.

- [ ] **Step 5: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/tracking_controls_test.exs`
Expected: PASS. (The two mount sites still reference `IntentControl` and fail to compile until Task 11; if the compiler blocks this run, do Task 11's mount-site edits first and come back.)

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/components/title/tracking_controls.ex storybook/title/tracking_controls.story.exs storybook/title/_title.index.exs test/media_centaur_web/components/title/tracking_controls_test.exs
git rm lib/media_centaur_web/components/title/intent_control.ex storybook/title/intent_control.story.exs test/media_centaur_web/components/title/intent_control_test.exs
git commit -m "feat(title): TrackingControls — Track release dates and Auto-grab over one record"
```

---

### Task 10: The bookmark removes at any rung

**Files:**
- Modify: `lib/media_centaur_web/components/title/watchlist_toggle.ex`
- Modify: `storybook/title/watchlist_toggle.story.exs:30-50`
- Test: `test/media_centaur_web/components/title/watchlist_toggle_test.exs`

- [ ] **Step 1: Rewrite the failing test**

Replace the whole file:

```elixir
defmodule MediaCentaurWeb.Components.Title.WatchlistToggleTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Title.WatchlistToggle

  describe "choice/1 — what a click on the bookmark sets" do
    test "off the list, or ignored: List" do
      assert WatchlistToggle.choice(nil) == "list"
      assert WatchlistToggle.choice(:ignored) == "list"
    end

    test "on the list at any rung: Off — removing from the watchlist is one act" do
      for rung <- [:list, :follow, :grab], do: assert(WatchlistToggle.choice(rung) == "off")
    end
  end

  describe "listed?/1 — the filled bookmark" do
    test "only a title at List or above is on the list" do
      refute WatchlistToggle.listed?(nil)
      refute WatchlistToggle.listed?(:ignored)
      for rung <- [:list, :follow, :grab], do: assert(WatchlistToggle.listed?(rung))
    end
  end

  describe "label/1 — the accessible name says what the click does" do
    test "names the act" do
      assert WatchlistToggle.label(nil) == "Add to watchlist"
      assert WatchlistToggle.label(:ignored) == "Add to watchlist"
      assert WatchlistToggle.label(:list) == "On your list — remove"
      assert WatchlistToggle.label(:grab) == "On your list — remove"
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/watchlist_toggle_test.exs`
Expected: FAIL — `choice(:follow)` is nil.

- [ ] **Step 3: Change the component**

In `lib/media_centaur_web/components/title/watchlist_toggle.ex`:

Replace the moduledoc's second paragraph with:

```
  Outline off the list, solid with the primary tint on it, state in
  `aria-pressed`. A click sets List for a title with no record or an
  ignored one, and Off for a title on the list at any rung — removing a
  title from the watchlist is one act (spec 2026-09-14). Off deletes the
  record and the calendar derived from it; re-listing derives it again,
  and the title's quality acceptance survives on its own. `choice/1` is
  that rule, carried as `phx-value-choice`, so the host's handler sets
  exactly what the control said it would rather than deciding again.
```

- `attr :rung` values: `[nil, :ignored, :list, :follow, :grab]`.
- `phx-click={@event}` (no `@choice &&`).
- Replace the `choice/1` doc and clauses:

```elixir
  @doc "What a click sets: `\"list\"` off the list or ignored; `\"off\"` at any listed rung."
  @spec choice(TitleIntent.rung() | nil) :: String.t()
  def choice(nil), do: "list"
  def choice(:ignored), do: "list"
  def choice(_listed), do: "off"
```

- Replace the `label/1` clauses:

```elixir
  @doc "The accessible name — what the click does."
  @spec label(TitleIntent.rung() | nil) :: String.t()
  def label(nil), do: "Add to watchlist"
  def label(:ignored), do: "Add to watchlist"
  def label(_listed), do: "On your list — remove"
```

In `storybook/title/watchlist_toggle.story.exs` replace the `:listed` variation description with `"At List: filled, and a click sets Off."` and the `:followed_marker` group with:

```elixir
      %VariationGroup{
        id: :followed,
        description:
          "At Follow and Grab: filled, and a click sets Off — removing from the watchlist is " <>
            "one act; the calendar is derived again when the title is re-listed.",
        variations:
          for rung <- [:follow, :grab] do
            %Variation{id: rung, attributes: base(%{rung: rung})}
          end
      }
```

- [ ] **Step 4: Run the test**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/watchlist_toggle_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/title/watchlist_toggle.ex storybook/title/watchlist_toggle.story.exs test/media_centaur_web/components/title/watchlist_toggle_test.exs
git commit -m "feat(title): the bookmark removes a title from the watchlist at any rung"
```

---

### Task 11: Mount sites and hosts

**Files:**
- Modify: `lib/media_centaur_web/components/title/detail_modal.ex:204-210` (+ alias)
- Modify: `lib/media_centaur_web/components/detail_panel.ex:154-158, 520-527, 636-664`
- Modify: `lib/media_centaur_web/live/entity_modal.ex:634, 964-968, 1034-1038, 1662-1695`
- Modify: `lib/media_centaur_web/live/home_live.ex:269`, `lib/media_centaur_web/live/library_live.ex:473`
- Modify: `lib/media_centaur_web/live/title_detail_host.ex:194-222, 228-245, 283-291, 526-533`
- Modify: `lib/media_centaur_web/live/discovery_live.ex:120, 639`
- Modify: `lib/media_centaur_web/live/incoming_live.ex:892`
- Modify: `lib/media_centaur_web/components/acquisition/media_results.ex:63-67, 208-217`

No new tests in this task; Task 13 rewrites the LiveView tests that cover these sites.

- [ ] **Step 1: The title detail modal**

`lib/media_centaur_web/components/title/detail_modal.ex`: change the alias `IntentControl` to `TrackingControls`; add `alias MediaCentaur.Settings.Preferences.PlanningMode` and `alias MediaCentaurWeb.Components.Title.Logic` if absent; replace the mount:

```heex
            <TrackingControls.tracking_controls
              id="title-tracking-controls"
              ref={@ref}
              rung={@detail.rung}
              media_type={@detail.title.media_type}
              release_ahead?={Logic.release_ahead?(@detail.title, @detail.release_window, @today)}
              complete?={@detail.complete?}
              approval_policy={PlanningMode.approval_policy(@detail.planning_mode)}
              acquisition?={@detail.acquisition?}
            />
```

The modal already takes `today` (its story passes it); if the attr is missing, add `attr :today, Date, required: true` and pass `today={@today}` from the host's render. Update the moduledoc line 49's event list if it names `IntentControl`.

- [ ] **Step 2: The library detail panel**

`lib/media_centaur_web/components/detail_panel.ex`:

- Line 156-158: replace `attr :default_grab_mode, :string, default: "off", doc: …` with `attr :approval_policy, :string, values: ["automatic", "review"], required: true, doc: "what a tracking plan is stamped with — whether an auto-grab asks first."`.
- Change the alias `IntentControl` to `TrackingControls`.
- The `tracking_block` call (lines 520-527):

```heex
            <.tracking_block
              tracking={@tracking}
              rung={@rung}
              ref={@title_ref}
              entity_type={@entity.type}
              approval_policy={@approval_policy}
              acquisition?={@acquisition?}
              lower_quality_accepted?={@lower_quality_accepted?}
            />
```

- `tracking_block`'s attrs: replace `attr :default_grab_mode, :string, required: true` with `attr :entity_type, :atom, required: true` and `attr :approval_policy, :string, required: true`. Replace the `IntentControl.intent_control` element with:

```heex
      <%!-- Complete is a film the library owns (ReleaseTracking.complete?/2);
            a series is never complete and a collection is filing
            (UIDR-025) whose next part's date the library does not hold —
            so both rows are offered and the record says which are on. --%>
      <TrackingControls.tracking_controls
        :if={@ref}
        id="detail-tracking-controls"
        ref={@ref}
        rung={@rung}
        media_type={if @entity_type == :tv_series, do: :tv_series, else: :movie}
        release_ahead?={true}
        complete?={false}
        approval_policy={@approval_policy}
        acquisition?={@acquisition?}
      />
```

- [ ] **Step 3: The library modal host**

`lib/media_centaur_web/live/entity_modal.ex`:

- Line 634: `approval_policy: PlanningMode.approval_policy(PlanningMode.value()),` replacing `default_grab_mode: AutoGrabSettings.load().default_mode,`. Remove the `AutoGrabSettings` alias if unused.
- Lines 964-968 (the `detail_modal` component attr): replace `attr :default_grab_mode, :string, required: true, doc: …` with `attr :approval_policy, :string, values: ["automatic", "review"], required: true, doc: "what a tracking plan is stamped with — whether an auto-grab asks first."`.
- Line 1036: `approval_policy={@approval_policy}`.
- `@rungs ~w(off list follow grab)`; `rung_atom/1` keeps only the `"off"`, `"list"`, `"follow"`, `"grab"` clauses.

`lib/media_centaur_web/live/home_live.ex:269` and `lib/media_centaur_web/live/library_live.ex:473`: `approval_policy={@approval_policy}`.

- [ ] **Step 4: The title detail host**

`lib/media_centaur_web/live/title_detail_host.ex`:

- Add `alias MediaCentaur.TMDB.ReleaseWindow`; remove the `AutoGrabSettings` alias.
- `build_detail/4`: delete `default_grab_mode = AutoGrabSettings.load().default_mode`; add `planning_mode = PlanningMode.value()` beside `today`; in `facts`: tracking context `approval_policy: PlanningMode.approval_policy(planning_mode)` (replacing `auto_grab_default_mode: default_grab_mode`), delete `default_grab_mode: default_grab_mode,`, change `planning_mode: PlanningMode.value(),` to `planning_mode: planning_mode,`, and add `complete?: ReleaseTracking.complete?(title.tmdb_id, title.media_type),` and `release_window: nil,`.
- `fetch_preview/2`: `start_async(socket, {:title_preview, ref}, fn -> load_preview(title, in_library?, socket.assigns.today) end)` (bind `today = socket.assigns.today` before the closure so the socket is not captured).
- `load_preview/3`:

```elixir
  # The movie payload also says where the film stands in its release
  # sequence — the fact that decides whether there is a release to track.
  defp load_preview(%Title{media_type: :movie, tmdb_id: id}, in_library?, today) do
    with {:ok, movie} <- TMDBClient.get_movie(id),
         do: {:ok, {TitlePreview.movie(movie, in_library?), ReleaseWindow.from_payload(movie, today)}}
  end

  defp load_preview(%Title{media_type: :tv_series, tmdb_id: id}, in_library?, _today) do
    with {:ok, show} <- TMDBClient.get_tv(id), do: {:ok, {TitlePreview.tv(show, in_library?), nil}}
  end
```

- The preview async clause:

```elixir
  def handle_title_async(
        {:title_preview, ref},
        {:ok, {:ok, {%TitlePreview{} = preview, window}}},
        socket
      ) do
    case socket.assigns.title_detail do
      %TitleDetail{ref: ^ref} = detail ->
        {:halt, assign(socket, :title_detail, %{detail | preview: preview, release_window: window})}

      _closed_or_other ->
        {:halt, socket}
    end
  end
```

- `rung_atom/1`: keep only `"off"`, `"list"`, `"follow"`, `"grab"`. Check the `set_rung` handler's guard (it may list the accepted strings) and narrow it the same way.

- [ ] **Step 5: Discovery, Incoming, media results**

`lib/media_centaur_web/live/discovery_live.ex`: delete line 120 (`default_grab_mode:` assign) and line 639 (`default_grab_mode: @default_grab_mode,` in the row-markers map); remove the `AutoGrabSettings` alias if unused.

`lib/media_centaur_web/live/incoming_live.ex:892`: delete `default_grab_mode={@auto_grab_default_mode}`.

`lib/media_centaur_web/components/acquisition/media_results.ex`: delete the `attr :default_grab_mode` block (lines 63-67) and `default_grab_mode: assigns.default_grab_mode` from `markers/2` (with the trailing comma fix on the previous line).

`lib/media_centaur_web/components/discovery/feed_entry_card.ex`: line 119, the state word becomes `Tracking` (the `:following` atom stays — code says follow, the UI says track, the same split the guide vocabulary uses); line 15 of the moduledoc, `"Following"` → `"Tracking"`. In `feed_entry.ex` line 11 leave the atom, and note the rendered word is "Tracking".

- [ ] **Step 6: Compile clean**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors`
Expected: compiles with no warnings. Fix any unused alias the compiler names.

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur_web
git commit -m "refactor(web): mount TrackingControls; hosts carry the approval policy, completeness and the release window"
```

---

### Task 12: Story fixtures on the new rung set

**Files:**
- Modify: `storybook/title/title_detail_modal.story.exs:70-82, 340-360`
- Modify: `storybook/detail_panel/detail_panel.story.exs:722-734, 902-912`
- Modify: `storybook/acquisition/plan_modal.story.exs:360-372`
- Modify: `storybook/acquisition/media_results.story.exs` (every `default_grab_mode:` line)

- [ ] **Step 1: Edit the fixtures**

- `title_detail_modal.story.exs`: in `detail/2` delete `default_grab_mode: "ask"` (the struct's `release_window: nil`, `complete?: false` and `planning_mode: :manually_select_release` defaults apply; the movie fixture's future `release_date` makes a release ahead); every `rung: :default` becomes `rung: :grab`; the `:forecast_only` description "the grab modes stay selectable" becomes "the rows stay, and the note says nothing downloads until it is".
- `detail_panel.story.exs`: `rung: :default` → `rung: :grab`; `default_grab_mode: "all_releases"` → `approval_policy: "automatic"` at line 731; delete `default_grab_mode: "all_releases",` from the `TrackingDetail` fixture at line 908.
- `plan_modal.story.exs`: the rung list becomes `[:ignored, :list, :follow, :grab]`; its description "the marker — nothing to click — at List and above" stands (the empty-board footer's marker is `WatchlistToggle.listed?/1`, unchanged).
- `media_results.story.exs`: delete every `default_grab_mode: "off"` line (fix trailing commas).

Search `storybook/` for any remaining `:ask`, `:default` rung or `default_grab_mode` and fix it.

- [ ] **Step 2: Run the story suites**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: PASS. If the render test reports a stale "undefined function" for `tracking_controls/1`, run `MIX_ENV=test ~/scripts/agents/agent-mix compile --force` once (see memory: storybook stale undefined-function diagnostics).

- [ ] **Step 3: Commit**

```bash
git add storybook
git commit -m "chore(storybook): fixtures on the four-rung ladder and the planning mode"
```

---

### Task 13: LiveView and remaining unit tests

**Files:**
- Modify: `test/media_centaur_web/live/discovery_live_test.exs`
- Modify: `test/media_centaur_web/live/entity_modal_tracking_test.exs`
- Modify: `test/media_centaur_web/live/discovery_live/feed_entries_test.exs:131`
- Modify: `test/media_centaur/activities/publisher_test.exs:129-130`
- Modify: `test/media_centaur/release_tracking/set_rung_test.exs`
- Modify: `test/support/factory.ex:895-907`

- [ ] **Step 1: The factory's default rung**

In `test/support/factory.ex` `create_tracking_item/1`: `{rung, attrs} = Map.pop(attrs, :rung, :grab)` and the doc "`:rung` picks where the record sits (default `:grab`)". Drop the parenthetical about the global setting.

- [ ] **Step 2: Unit tests on the rung set**

- `set_rung_test.exs`: every `[:follow, :ask, :grab, :default]` becomes `[:follow, :grab]`.
- `feed_entries_test.exs:131`: `for rung <- [:follow, :grab],`.
- `publisher_test.exs:129-130`: `{:ok, _intent} = ReleaseTracking.set_rung(show(), :grab)` with the comment `# Raising within the list publishes nothing new.`
- Run `grep -rn '"Following"\|>Following<' test` and change every rendered-word assertion for the Feed card's state to `Tracking` (the `:following` atom assertions stay).

- [ ] **Step 3: The library modal test**

`test/media_centaur_web/live/entity_modal_tracking_test.exs`:

- Moduledoc: "the ladder control always" → "the tracking rows always".
- Setup: `rung: :grab`.
- First test: rename to "a tracked series carries the timeline and the rows under its seasons; no bell"; replace the `#detail-tracking-mode[data-rung='default']` assertion with `assert has_element?(view, "#detail-tracking-controls[data-rung='grab']")` and `assert has_element?(view, "#detail-tracking-controls-track[aria-disabled='true']")`; replace the two bookmark lines and their comment with:

```elixir
    # Listed at any rung: the bookmark is filled and a click removes the
    # title — one act (spec 2026-09-14).
    assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='true'][phx-value-choice='off']")
```

- Second test, replace whole body:

```elixir
  test "the rows move the rung; the bookmark deletes the tracked title and its timeline", %{
    conn: conn,
    series: series,
    item: item
  } do
    {:ok, view, _html} = live(conn, "/library?selected=#{series.id}")

    view |> element("#detail-tracking-controls-grab") |> render_click()
    await_supervised_tasks()
    assert Discovery.rung(424_242, :tv_series) == :follow
    assert has_element?(view, "#detail-tracking-controls[data-rung='follow']")
    assert has_element?(view, "#detail-release-timeline")

    view |> element("#detail-watchlist-toggle") |> render_click()
    await_supervised_tasks()

    assert Discovery.rung(424_242, :tv_series) == nil
    refute ReleaseTracking.get_item(item.id), "Off deletes the tracked title"
    assert has_element?(view, "#detail-tracking-controls[data-rung='off']")
    refute has_element?(view, "#detail-release-timeline")
  end
```

- Third test: rename to "an owned series not on the list offers Add to watchlist; the rows follow, and raise it"; `#detail-tracking-mode` → `#detail-tracking-controls` throughout; `refute has_element?(view, "#detail-tracking-mode-ask")` → `refute has_element?(view, "#detail-tracking-controls-track")`; the raise becomes `view |> element("#detail-tracking-controls-grab") |> render_click()` asserting `:grab`.

- [ ] **Step 4: The Discovery test**

`test/media_centaur_web/live/discovery_live_test.exs`, in order:

- Line 84: `assert has_element?(view, "#title-tracking-controls-track")`.
- Line 89: `assert has_element?(view, "#title-tracking-controls[data-form='controls']")` followed by `refute has_element?(view, "#title-tracking-controls-grab")` and the comment `# An owned movie is complete: the block is there and empty.`
- The "two acts" test (lines ~780-821): from `assert has_element?(view, "#title-tracking-mode[data-rung='off'][data-form='none']")` onward, replace with:

```elixir
      assert has_element?(view, "#title-tracking-controls[data-rung='off'][data-form='none']")
      refute has_element?(view, "#title-tracking-controls [data-nav-item]")

      view |> element("#title-watchlist") |> render_click()

      assert Discovery.rung(777, :movie) == :list
      assert has_element?(view, "#title-watchlist[aria-pressed='true'][phx-value-choice='off']")
      assert has_element?(view, "#title-tracking-controls[data-rung='list'][data-form='controls']")
      # The movie is out: nothing left to track, so Auto-grab alone.
      refute has_element?(view, "#title-tracking-controls-track")
      assert has_element?(view, "#title-tracking-controls-grab[phx-value-choice='grab']")

      # Grabbing fetches the calendar, so the movie is stubbed with a date to come.
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_get_movie(
        777,
        TmdbStubs.movie_detail(%{"id" => 777, "release_date" => "2999-01-01"})
      )

      view |> element("#title-tracking-controls-grab") |> render_click()
      await_supervised_tasks()
      assert Discovery.rung(777, :movie) == :grab
      # The bookmark still removes — one act, at any rung.
      assert has_element?(view, "#title-watchlist[aria-pressed='true'][phx-value-choice='off']")

      view |> element("#title-watchlist") |> render_click()
      assert Discovery.rung(777, :movie) == nil
      assert has_element?(view, "#title-watchlist[aria-pressed='false']")
      assert has_element?(view, "#title-tracking-controls[data-form='none']")
    end
```

- The ignored test: `#title-tracking-mode[…]` → `#title-tracking-controls[…]`; the final assertion becomes `assert has_element?(view, "#title-tracking-controls-grab")`.
- Delete the test "the tracking controls' Ignore removes the entry and keeps the modal; no Ignore on the watchlist" (a behaviour test for a removed control, not a regression test under ADR-027). Keep its first half's assertion elsewhere if no other test proves the watchlist row has no Ignore: the Feed-card Ignore test at ~721 already asserts `#watchlist-item-…-ignore` is absent on the watchlist tab; if not, add `refute has_element?(view, "#watchlist-item-movie-777-ignore")` to that test.
- Line ~898: `refute has_element?(view, "#title-detail-modal #title-tracking-controls")`.
- Line ~1053: same rename.
- The "upcoming series at List → Ask" test (~1240-1263): `#title-tracking-mode[data-rung='list']` → `#title-tracking-controls[data-rung='list']`; click `#title-tracking-controls-grab`; assert `:grab`; `render_until … [data-rung='grab']`; marker `"Auto-grab"`.
- The "moving the rung on a followed title; Off deletes the record and the row" test (~1266-1280):

```elixir
      {:ok, _} = Discovery.put_rung(released_movie(), :follow)
      item = create_tracking_item(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})

      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")
      assert has_element?(view, "#title-tracking-controls[data-rung='follow']")

      view |> element("#title-tracking-controls-grab") |> render_click()
      assert Discovery.rung(777, :movie) == :grab
      assert has_element?(view, "#title-tracking-controls[data-rung='grab']")

      view |> element("#title-watchlist") |> render_click()
      assert Discovery.rung(777, :movie) == nil
      refute ReleaseTracking.get_item(item.id), "Off deletes the tracked title too"
      refute has_element?(view, "#title-release-timeline")
      await_supervised_tasks()
```

- Line ~1295: marker `"Tracking"`.
- The "Off forgets the title and drops both its row and the modal" test (~1349): the click becomes `view |> element("#title-watchlist") |> render_click()`; line ~1355 `refute has_element?(view, "#title-tracking-controls")`.
- Search the file for any remaining `title-tracking-mode`, `:ask`, `:default`, `"Tracking: ` and fix.

- [ ] **Step 5: Run the affected suites**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/live/entity_modal_tracking_test.exs test/media_centaur_web/live/discovery_live/feed_entries_test.exs test/media_centaur/activities/publisher_test.exs test/media_centaur/release_tracking/set_rung_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add test
git commit -m "test: the tracking rows, the one-click bookmark, and the four-rung ladder"
```

---

### Task 14: Showcase seeds at Grab

**Files:**
- Modify: `lib/media_centaur/showcase.ex:574, 589`

- [ ] **Step 1: Change both `set_rung(title, :default)` to `set_rung(title, :grab)`**

- [ ] **Step 2: Compile**

Run: `~/scripts/agents/agent-mix compile --warnings-as-errors`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add lib/media_centaur/showcase.ex
git commit -m "chore(showcase): tracked titles seed at Grab"
```

---

### Task 15: Records — UIDR-042, glossary, wiki, changelog

**Files:**
- Create: `decisions/user-interface/2026-09-14-042-tracking-is-the-bookmark-and-two-switches.md`
- Modify: `decisions/user-interface/2026-09-07-036-one-control-per-title.md`
- Modify: `decisions/README.md` (regenerated)
- Modify: `docs/GLOSSARY.md:55-61, 63, 66`
- Modify: `~/src/media-centaur/media-centaur.wiki/Watchlist.md`, `Release-Tracking.md`, `Settings-Reference.md`
- Modify: `CHANGELOG.md` (draft under an `## Unreleased` heading; `/ship` finalises it)

- [ ] **Step 1: UIDR-042**

```markdown
---
status: accepted
date: 2026-09-14
---
# Tracking is the bookmark and two switches over one record

Supersedes UIDR-036 rules 1, 4 (its bookmark exception) and 5. Design: `docs/superpowers/specs/2026-09-14-tracking-controls-design.md`.

## Context and Problem Statement

The seven-way strip (Ignore · Off · List · Follow · Ask · Grab · Default) put three questions on one control and offered two exits as if they were levels. List restated what the bookmark already said; Off and Ignore were exits, not answers; Follow meant nothing for a title already out; and Ask, Grab and Default were three spellings of one per-title policy that already existed globally as the Download button's planning mode.

## Decision Outcome

Chosen option: "three controls for three questions", because a person's intent about a title is on my list / keep its calendar / plan its releases, in that order, and who commits a plan is one preference.

1. **The bookmark is membership.** It lists a title and removes it at any rung. Removal deletes the record and the calendar derived from it; re-listing derives it again.
2. **Track release dates is Follow.** A Settings-kit toggle row, shown only while a release is ahead: an unreleased movie, or any series. Its description says what Coming up will show.
3. **Auto-grab is Grab.** A toggle row shown for any title the library does not own outright. Its description says whether a drop downloads without asking or parks for approval, as the person's planning mode says, and where that is set.
4. **The ladder is Ignored · List · Follow · Grab.** No per-title grab policy; `PlanningMode.approval_policy/1` stamps every plan. The global "When a release appears" setting is deleted.
5. **Ignore belongs to the Feed.** It stays the Feed card's verb and leaves the title view.

### Consequences

* Good, because each control reads as a yes/no the person recognises, and the Download button and auto-grab ask first under the same rule.
* Good, because two global answers to one question became one.
* Bad, because the global setting can no longer move every title at once; auto-grab is set per title.
* Bad, because nothing notifies on a tracked release — Coming up is the surface. A follow-up pill source is scheduled in the spec.
```

- [ ] **Step 2: Amend UIDR-036**

Append to `decisions/user-interface/2026-09-07-036-one-control-per-title.md`, and set `amended: 2026-09-14` in its front matter:

```markdown
## Amendment 2026-09-14

Rules 1, 4's bookmark exception and 5 are superseded by [UIDR-042](2026-09-14-042-tracking-is-the-bookmark-and-two-switches.md): the seven-way strip became the bookmark and two switches, the ladder lost Ask and Default, and the bookmark removes at any rung. The premise stands — one record, one ladder (ADR-066) — and rules 2 and 3 stand as written.
```

Run: `scripts/gen-decisions-index`.

- [ ] **Step 3: Glossary**

In `docs/GLOSSARY.md`:

- **Rung**: `:ignored`, `:list`, `:follow`, `:grab` (UI: Ignore on the Feed card, the bookmark, Track release dates, Auto-grab). Keep the Off sentence. Replace the `:default` sentence with "There is no per-title grab policy: `TitleIntent.grabs?/1` says whether a title plans its drops, and `Settings.Preferences.PlanningMode` says whether the plan asks first."
- **Ignored**: replace "or the tracking controls' Ignore segment" with "— the one way onto the rung".
- **Tracking controls**: "The switch rows a listed title shows beneath its details: Track release dates (Follow) and Auto-grab (Grab), `Components.Title.TrackingControls` (UIDR-042). Shown only for a title on the list (`TrackingControls.control_form/1`), with the rows `rows/1` decides: a movie the library owns has none, a movie that is out has Auto-grab only. A download never moves a rung."
- **Bookmark**: "Sets List for a title with no record or an ignored one, Off for one on the list at any rung — removing from the watchlist is one act (UIDR-042)."
- **Following**: replace "The rungs above it change what happens to a release" with "Grab, the one rung above it, plans a release when it drops".
- **Approval policy**: replace "(the drop planner from the item's auto-grab mode; …)" with "(the drop planner and the Download button from the person's planning mode, `PlanningMode.approval_policy/1`; the picker and Plan now as `review`)".
- **Planning mode**: append "Also the approval policy every tracking plan is stamped with (UIDR-042)."

- [ ] **Step 4: Wiki**

In `~/src/media-centaur/media-centaur.wiki/`:

`Watchlist.md`:
- Line 17 → "The bookmark takes a title off your list at any point — one click. That also stops tracking and auto-grab for it; add it again and the calendar is fetched again."
- Replace the Tracking section (the paragraph at line 31 through the note at line 49) with:

```markdown
Once a title is on your list, its view shows two switches below the details.

| Switch | What it does |
|---|---|
| **Track release dates** | Keeps the title's release calendar. A movie's theatrical, digital and disc dates, or a series' upcoming episodes, show under **Coming up** on Incoming. Shown only while a release is still ahead — a movie that is already out has nothing to track |
| **Auto-grab** | When a release drops, Media Centaur plans it. Whether the plan downloads without asking or waits for your approval on Incoming is your Download button default under **Settings → Acquisition** — the same choice a manual download uses. Turning Auto-grab on keeps Track release dates on |

- **Nothing sets this but you.** Adding a series to your library does not start tracking it, and neither does downloading one. Only these switches do, and they appear once the title is on your list.
- A movie already in your library is complete and shows no switches.

With no [Prowlarr](Prowlarr-Integration) configured, Auto-grab has nothing to act on; the switch still records what you want, and the first healthy pass plans the backlog.
```

- Line 25's "the tracking level when the title is being followed" → "**Tracking** or **Auto-grab** when a switch is on".
- Line 53: "the tracking control, and beneath it — once the title is followed —" → "the two switches, and beneath them — once Track release dates is on —".
- Line 65: "set its tracking to **Follow** or higher instead" → "turn on **Track release dates** instead".
- Line 75: "and Follow from here brings the release to Coming up" → "and **Track release dates** from there brings the release to Coming up".

`Release-Tracking.md`:
- Line 7: "because you set it to **Follow** or higher" → "because you turned on **Track release dates** or **Auto-grab** for it".
- Line 22: "a followed series in Default or Grab wants every episode it is missing. If you do not want those searched for, open the row and set the title's tracking to Follow or Off" → "a series with **Auto-grab** on wants every episode it is missing. If you do not want those searched for, open the row and turn Auto-grab off".
- Line 32 (**Tracked** pill): "(auto-grab is off for it, or Prowlarr isn't configured)" → "(Auto-grab is off for it, your Download button default asks first, or Prowlarr isn't configured)".
- Line 49: "set its tracking to **Follow** or higher" → "turn on **Track release dates** (or **Auto-grab**)".
- Replace lines 57-63 (the "What happens to that plan…" paragraph and its bullets) with:

```markdown
What happens to that plan is your Download button default under **Settings → Acquisition**:

- **Auto-select best release** — the plan is approved and grabbed automatically. Every grab shows up on the Incoming page with full provenance.
- **Manually select release** (the default) — the plan parks as a ready draft on the Incoming page; you review and approve (or steer, or discard) it yourself. Parked drafts never expire.

A title with **Track release dates** on and **Auto-grab** off is never planned; its releases only show on Coming up.
```

- Line 73: "sets a single title's mode" → "the switches set a single title".
- Line 75: "**Dropping a title to Follow or Off**" → "**Turning Auto-grab off, or removing the title from your watchlist,**".
- Line 82: "set to **Follow** or higher yourself" → "you switched on yourself".
- Line 90: "auto-acquisition defaults" → "auto-acquisition quality settings".

`Settings-Reference.md`:
- Line 144 row: append to the options cell "Also decides whether **Auto-grab** on a watchlist title asks first — see [Watchlist → Tracking](Watchlist#tracking)."
- Line 148: "Applied when a tracked title's release appears — see … A title's own tracking controls take precedence." → "Applied to every release Auto-grab takes — see [Release Tracking → Automatic downloads](Release-Tracking#automatic-downloads)."
- Delete the **When a release appears** row (line 152).

Commit the wiki separately: `cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: tracking is two switches; the auto-grab default mode is gone"` (do not push).

- [ ] **Step 5: Changelog draft**

Add under a new `## Unreleased` heading at the top of `CHANGELOG.md` (the ship flow renames it):

```markdown
### Improved

- **Tracking a watchlist title is two switches.** Under a listed title's details, **Track release dates** keeps its calendar so its dates show on Coming up, and **Auto-grab** plans each release when it drops. The seven-way strip (Ignore · Off · List · Follow · Ask · Grab · Default) is gone: the bookmark beside Download is the whole of on-or-off-the-list, and removes a title at any point; Ignore stays on the Feed card. A movie that is already out shows only Auto-grab, and a movie in your library shows neither.
- **One rule for asking first.** Whether an auto-grab downloads without asking or waits for your approval is now your Download button default under Settings → Acquisition, the same choice a manual download uses. The separate **When a release appears** setting is gone. Titles that were set to Ask or Grab are now Auto-grab; titles that followed the global setting are Auto-grab, or Track release dates only if that setting was *Notify only*.
```

- [ ] **Step 6: Commit**

```bash
git add decisions docs/GLOSSARY.md CHANGELOG.md
git commit -m "docs: UIDR-042 — tracking is the bookmark and two switches; glossary and changelog"
```

---

### Task 16: Precommit and review

- [ ] **Step 1: Sweep for leftovers**

Run: `grep -rn "grab_mode\|default_grab_mode\|auto_grab_default_mode\|IntentControl\|intent_control\|:ask\b\|Tracking: " lib storybook test docs/GLOSSARY.md | grep -v "_build\|node_modules"`
Expected: no hits in `lib`, `storybook`, `test` or the glossary (the spec and this plan may mention them; `decisions/` history may).

- [ ] **Step 2: Full precommit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: format clean, credo clean (MC0009 sees `tracking_controls.story.exs` for `tracking_controls/1`), boundaries clean, no warnings, all tests green. Fix everything it reports.

- [ ] **Step 3: Run the data migration against the dev database**

Run: `~/scripts/agents/agent-mix ecto.migrate_data`
Expected: the migration runs once; a second run is a no-op. Open a listed title on the dev server (`http://localhost:2160/discovery/watchlist`) and confirm the two rows render and flip the rung; confirm Settings → Acquisition no longer shows *When a release appears*.

- [ ] **Step 4: Commit any precommit fixes**

```bash
git add -A
git commit -m "chore: precommit fixes for the tracking controls"
```

Report back with the precommit output and the dev-server observation. Do not push; do not run `/ship`.

---

## Self-review

- **Spec coverage.** Record and `grabs?` — Task 1, 2. Planning mode owns the policy; second global setting deleted — Task 2, 3. Migration — Task 4. Acquisition readers — Task 5. Forecast and tracking detail — Task 6. Release ahead, markers, detail — Task 7. Toggle row `id`/`disabled?` — Task 8. The component, story, test; IntentControl deleted — Task 9. Bookmark at any rung — Task 10. Mount sites, hosts, release window — Task 11. Fixtures — Task 12. LiveView tests, factory — Task 13. Showcase — Task 14. UIDR-042, UIDR-036 amendment, glossary, wiki, changelog — Task 15. Scheduled convergence (the pill) is recorded in the spec and UIDR-042, not built.
- **Type consistency.** `TrackingControls` attrs: `id, ref, rung, media_type, release_ahead?, complete?, approval_policy, acquisition?` — used identically in Task 9 (component, story, test) and Task 11 (both mounts). `Title.Detail` gains `release_window` and `complete?`, loses `default_grab_mode` (Task 7); the modal derives `release_ahead?` with `Logic.release_ahead?/3` and the policy with `PlanningMode.approval_policy/1` at the mount (Task 11). `UpcomingFeed`/`View`/`TrackingDetail` context key `approval_policy` (Task 6) is what Tasks 6 and 11 pass. `PlanningMode.approval_policy/1` (Task 2) is what Tasks 2, 5, 6 and 11 call. `Discovery.grabs?/2` (Task 2) is what Task 5 calls. `ReleaseTracking.complete?/2` (Task 2) is what Task 11's host and `ReleaseTracking` itself call.
- **Placeholders.** None: every code step carries its code; every edit names its lines.
