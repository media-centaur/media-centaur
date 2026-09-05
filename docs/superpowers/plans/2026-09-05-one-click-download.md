# One-click download from Discovery — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A recommendation or watchlist row opens a title detail modal whose Download creates a plan that commits itself when clean, with the sidebar showing a follow-up pill on Incoming when a plan parks for review.

**Architecture:** Three seams, each unified with what exists. (1) `approval_policy` becomes a stamped column on every plan and the Reactor gate reads only it. (2) One `TitleDetailModal` under `CinematicShell` serves both Discovery tabs, built from a pure `TitleDetail` view-model; rows become whole-card click targets showing acquisition state. (3) `ShellBadges` carries one `Counts` struct into `Layouts.app`, rendered by one `follow_up_pill` component on Incoming, Review, and Status.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto (SQLite), Oban (inline in tests), Phoenix Storybook, the input-system nav config (JS), bun tests.

**Spec:** `docs/superpowers/specs/2026-09-05-one-click-download-design.md`. Read it first. Every task below cites the spec decision it implements.

**Conventions that apply to every task:**
- Run every `mix` command as `mise exec -- mix …` (stale PATH otherwise picks OTP 28 and crash-loops the dev service).
- Test first: write the failing test, run it, see it fail for the right reason, implement, run again.
- No real show titles anywhere (`Sample Show`, `Sample Movie`).
- Commit after every task with a conventional-commit message. Do not push.
- After the last task run `mise exec -- mix precommit` and fix everything it reports.
- Skills to load before the task's code: `elixir-thinking` (all), `ecto-thinking` (Task 1–2), `otp-thinking` (Task 6), `phoenix-thinking` + `user-interface` + `storybook` (Tasks 8–13), `input-system` (Task 14), `writing-copy` (any user-facing string).

---

## File map

| File | Responsibility | Task |
|---|---|---|
| `priv/repo/migrations/20260905120000_add_plan_approval_policy.exs` | the column | 1 |
| `lib/media_centaur/acquisition/plans/plan.ex` | schema field + validation | 1 |
| `lib/media_centaur/acquisition/plans.ex` | stamping via opts, `clean?/1`, `count_awaiting_review/0`, `plan_title/2` | 2, 3, 4, 6 |
| `lib/media_centaur/acquisition/drop_planner.ex` | stamps from the item's mode | 2 |
| `lib/media_centaur/acquisition/reactor/handlers.ex` | the gate reads the column | 3 |
| `lib/media_centaur/acquisition/plans/download_scope.ex` | pure: first-season / everything unit selection | 5 |
| `lib/media_centaur/acquisition/title_states.ex` | per-title acquisition state for a list of refs | 7 |
| `lib/media_centaur_web/shell_badges.ex` | `Counts` struct, new source | 8 |
| `lib/media_centaur_web/components/follow_up_pill.ex` | the one pill component | 9 |
| `lib/media_centaur_web/components/layouts.ex` | `badges` attr, pill on three entries, dot moves | 9 |
| every LiveView `render/1` that calls `Layouts.app` | pass `badges` | 9 |
| `assets/css/app.css` | pill placement in both rail widths; `.sort-dropdown-*` → `.glass-menu-*` | 9, 11 |
| `lib/media_centaur_web/components/discovery/title_detail.ex` | view-model struct | 10 |
| `lib/media_centaur_web/live/discovery_live/logic.ex` | pure builders for the view-model and row markers | 10 |
| `lib/media_centaur_web/components/discovery/title_detail_modal.ex` | the modal + split download control | 11 |
| `lib/media_centaur_web/components/discovery/title_row.ex` (replaces `watchlist_row.ex` and `feed_row.ex`) | one click-target row with state markers | 12 |
| `lib/media_centaur_web/live/discovery_live.ex` | URL-driven modal, events, acquisition subscription | 13 |
| `assets/js/input/config.js` | `title_detail` overlay | 14 |
| `storybook/discovery/title_detail_modal.story.exs`, `storybook/navigation/follow_up_pill.story.exs`, `storybook/discovery/title_row.story.exs` | contracts | 9, 11, 12 |
| `test/media_centaur_web/page_smoke_test.exs` | `?title=` entries | 13 |
| `decisions/user-interface/2026-09-05-030-follow-up-pill-and-condition-dot.md`, `decisions/README.md`, `docs/GLOSSARY.md`, ADR-056 note, wiki | records | 15 |

---

### Task 1: `approval_policy` column and schema field

Spec decisions 1, "Data changes".

**Files:**
- Create: `priv/repo/migrations/20260905120000_add_plan_approval_policy.exs`
- Modify: `lib/media_centaur/acquisition/plans/plan.ex`
- Test: `test/media_centaur/acquisition/plans/plan_test.exs` (create if absent; check with `ls test/media_centaur/acquisition/plans/`)

- [x] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Acquisition.Plans.PlanTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Plans.Plan

  @base %{tmdb_id: "777", tmdb_type: "movie", title: "Sample Movie"}

  describe "create_changeset/1 approval_policy" do
    test "defaults to review" do
      changeset = Plan.create_changeset(@base)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :approval_policy) == "review"
    end

    test "accepts automatic" do
      changeset = Plan.create_changeset(Map.put(@base, :approval_policy, "automatic"))
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :approval_policy) == "automatic"
    end

    test "rejects any other value" do
      changeset = Plan.create_changeset(Map.put(@base, :approval_policy, "approve"))
      refute changeset.valid?
      assert %{approval_policy: ["is invalid"]} = errors_on(changeset)
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
```

- [x] **Step 2: Run it**

Run: `mise exec -- mix test test/media_centaur/acquisition/plans/plan_test.exs`
Expected: FAIL — `approval_policy` is not a field (`get_field` returns nil, first test fails on `nil == "review"`).

- [x] **Step 3: Migration**

```elixir
defmodule MediaCentaur.Repo.Migrations.AddPlanApprovalPolicy do
  use Ecto.Migration

  @moduledoc """
  Adds the per-plan approval policy: `automatic` (the Reactor gate
  commits the plan itself once it solves cleanly) or `review` (a person
  approves it on Downloads). Every existing row is either terminal
  (committed / discarded) or a user-facing draft, so `review` is the
  correct value for all of them — no backfill. Reversible: dropping the
  column loses nothing the gate can't re-derive for terminal rows.
  """

  def change do
    alter table(:acquisition_plans) do
      add :approval_policy, :string, null: false, default: "review"
    end
  end
end
```

- [x] **Step 4: Schema**

In `lib/media_centaur/acquisition/plans/plan.ex`:

Add to the moduledoc after the lifecycle diagram:

```
  ## Approval policy

  `approval_policy` names who commits the plan once it is `ready`:
  `automatic` — the Reactor gate (`Reactor.Handlers.plan_changed/1`)
  commits it when the result qualifies (a clean plan for a manual plan,
  any found unit for a tracking plan); `review` — the plan parks as a
  draft on Downloads until a person approves it. Stamped at creation by
  whoever creates the plan (the drop planner from the item's auto-grab
  mode, the picker and plan-now as `review`, one-click downloads as
  `automatic`) and never derived from `origin` at read time.
```

Add the module attribute and field:

```elixir
  @approval_policies ~w(automatic review)
  ...
    field :approval_policy, :string, default: "review"
```

Add `:approval_policy` to the `cast` list in `create_changeset/1` and:

```elixir
    |> validate_inclusion(:approval_policy, @approval_policies)
```

Add a public accessor for callers that need the vocabulary:

```elixir
  @doc "The approval policy values."
  @spec approval_policies() :: [String.t()]
  def approval_policies, do: @approval_policies
```

- [x] **Step 5: Migrate and run**

Run: `mise exec -- mix ecto.migrate && mise exec -- mix test test/media_centaur/acquisition/plans/plan_test.exs`
Expected: PASS (3 tests).

- [x] **Step 6: Commit**

```bash
git add priv/repo/migrations/20260905120000_add_plan_approval_policy.exs lib/media_centaur/acquisition/plans/plan.ex test/media_centaur/acquisition/plans/plan_test.exs
git commit -m "feat(acquisition): approval_policy column on plans"
```

---

### Task 2: Every creator stamps the policy

Spec decision 2.

**Files:**
- Modify: `lib/media_centaur/acquisition/plans.ex` (`create_series_plan/3`, `create_movie_plan/2`)
- Modify: `lib/media_centaur/acquisition/drop_planner.ex` (`plan_now/3` both clauses, `plan_tv_drop/5`, `plan_movie_drop/5`)
- Test: `test/media_centaur/acquisition/plans_test.exs`, `test/media_centaur/acquisition/drop_planner_test.exs`

- [x] **Step 1: Failing tests — Plans**

Append to `test/media_centaur/acquisition/plans_test.exs` inside the module, a new describe (use the file's existing `selection/0` helper and its Prowlarr stub setup):

```elixir
  describe "approval policy stamping" do
    test "picker plans default to review" do
      {:ok, series} = Plans.create_series_plan(selection(), [{1, 1}])
      {:ok, movie} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})

      assert Plans.fetch!(series.id).approval_policy == "review"
      assert Plans.fetch!(movie.id).approval_policy == "review"
    end

    test "creators can stamp automatic" do
      {:ok, series} = Plans.create_series_plan(selection(), [{1, 1}], approval_policy: "automatic")

      {:ok, movie} =
        Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005},
          approval_policy: "automatic"
        )

      assert Plans.fetch!(series.id).approval_policy == "automatic"
      assert Plans.fetch!(movie.id).approval_policy == "automatic"
    end
  end
```

If `Plans.fetch!/1` does not exist, use `{:ok, plan} = Plans.fetch(id)` instead — do not add a bang variant just for the test.

- [x] **Step 2: Failing tests — DropPlanner**

In `test/media_centaur/acquisition/drop_planner_test.exs`, extend the existing test `"due wants become one tracking plan per title, auto-committed as one pursuit"` with one assertion after `[plan] = Repo.all(Plans.Plan)`:

```elixir
      assert plan.approval_policy == "automatic"
```

Find the existing ask-mode test in the same file (grep `"ask"`) and add, where it asserts the plan is `ready`:

```elixir
      assert plan.approval_policy == "review"
```

Find the existing `plan_item_now` test (grep `plan_item_now`) and add where it fetches the plan:

```elixir
      assert plan.approval_policy == "review"
```

- [x] **Step 3: Run**

Run: `mise exec -- mix test test/media_centaur/acquisition/plans_test.exs test/media_centaur/acquisition/drop_planner_test.exs`
Expected: the new assertions FAIL (`"review" == "automatic"` in the auto-mode test; the opt is ignored in "creators can stamp automatic").

- [x] **Step 4: Implement — Plans**

In `create_series_plan/3` and `create_movie_plan/2`, add to the attrs map passed to `create_plan/2`:

```elixir
        approval_policy: Keyword.get(opts, :approval_policy, "review"),
```

Update both `@doc`s with one sentence: "`approval_policy:` (`\"automatic\"` | `\"review\"`, default review) names who commits the plan once ready — see `Plan`."

`create_tracking_plan/2` passes `plan_attrs` through; the drop planner supplies the key.

- [x] **Step 5: Implement — DropPlanner**

In both `plan_now/3` clauses (origin `"manual"` plan-now drafts) add to the plan attrs:

```elixir
               approval_policy: "review",
```

In `plan_tv_drop/5` and `plan_movie_drop/5` (the tick's origin `"tracking"` plans — read the rest of the file to find the `Plans.create_tracking_plan` calls) add:

```elixir
               approval_policy: approval_policy(item, settings),
```

and the private helper near `bounds/2`:

```elixir
  # The item's mode at creation decides the policy (spec 2026-09-05 §2):
  # ask parks for a person, every other grabbing mode lets the gate
  # commit. `off` items never reach here (`plan_item/4` guards it).
  defp approval_policy(%Item{} = item, settings) do
    case AutoGrabSettings.effective_mode(item.auto_grab_mode, settings) do
      "ask" -> "review"
      _grabbing_mode -> "automatic"
    end
  end
```

Update the DropPlanner moduledoc's pipeline sentence: "RunPlan → mode gate → CommitPlan" becomes "RunPlan → the approval gate (`Reactor.Handlers.plan_changed/1`, reading the stamped `approval_policy`) → CommitPlan".

- [x] **Step 6: Run**

Run: `mise exec -- mix test test/media_centaur/acquisition/plans_test.exs test/media_centaur/acquisition/drop_planner_test.exs`
Expected: PASS.

- [x] **Step 7: Commit**

```bash
git add lib/media_centaur/acquisition/plans.ex lib/media_centaur/acquisition/drop_planner.ex test/media_centaur/acquisition/plans_test.exs test/media_centaur/acquisition/drop_planner_test.exs
git commit -m "feat(acquisition): every plan creator stamps approval_policy"
```

---

### Task 3: The gate reads the column; `Plans.clean?/1`

Spec decisions 3, 4, 5, 6.

**Files:**
- Modify: `lib/media_centaur/acquisition/reactor/handlers.ex`
- Modify: `lib/media_centaur/acquisition/plans.ex` (`clean?/1`)
- Create: `test/media_centaur/acquisition/reactor/handlers_test.exs`

- [x] **Step 1: Failing tests**

```elixir
defmodule MediaCentaur.Acquisition.Reactor.HandlersTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.{PlanEvents, Plans}
  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.Acquisition.Reactor.Handlers

  @movie %{tmdb_id: "246813", title: "Sample Movie", year: 2005}

  setup do
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
    )

    :ok
  end

  # Prowlarr answers every search with the given releases; indexer
  # health reads as unconfigured (not blind) so the corpus records.
  defp stub_search(releases) do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/indexer"} -> Req.Test.json(conn, [])
        {"GET", "/api/v1/indexerstatus"} -> Req.Test.json(conn, [])
        {"GET", "/api/v1/search"} -> Req.Test.json(conn, releases)
        {"POST", "/api/v1/search"} -> Req.Test.json(conn, %{"approved" => true})
        _other -> Req.Test.json(conn, %{})
      end
    end)
  end

  defp release(title, guid, quality_seeders) do
    %{
      "title" => title,
      "guid" => guid,
      "indexerId" => 1,
      "indexer" => "indexer-a",
      "seeders" => quality_seeders
    }
  end

  defp acceptable_movie, do: [release("Sample.Movie.2005.1080p.WEB-DL", "movie-1080p", 20)]
  defp below_floor_movie, do: [release("Sample.Movie.2005.720p.WEB-DL", "movie-720p", 20)]

  defp gate(plan) do
    {:ok, plan} = Plans.fetch(plan.id)
    Handlers.plan_changed(%PlanEvents.Changed{plan_id: plan.id, status: plan.status})
    {:ok, reloaded} = Plans.fetch(plan.id)
    reloaded
  end

  describe "plan_changed/1 — manual plans" do
    test "automatic + clean commits one pursuit" do
      stub_search(acceptable_movie())
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      committed = gate(plan)

      assert committed.status == "committed"
      assert [%Pursuit{origin: "manual"}] = Repo.all(Pursuit)
    end

    test "automatic + a gap stays ready" do
      stub_search([])
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      assert gate(plan).status == "ready"
      assert Repo.all(Pursuit) == []
    end

    test "automatic + only below-preference candidates stays ready" do
      stub_search(below_floor_movie())
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      assert gate(plan).status == "ready"
      assert Repo.all(Pursuit) == []
    end

    test "review never commits, even when clean" do
      stub_search(acceptable_movie())
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "review")

      assert gate(plan).status == "ready"
      assert Repo.all(Pursuit) == []
    end

    test "automatic + an approval rejection stays ready" do
      stub_search(acceptable_movie())
      # An active pursuit already claims the movie → CommitPlan rejects with overlap.
      create_pursuit(%{tmdb_id: "246813", tmdb_type: "movie", title: "Sample Movie", origin: "manual"})
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      assert gate(plan).status == "ready"
      assert length(Repo.all(Pursuit)) == 1
    end
  end

  describe "clean?/1" do
    test "true only when every non-excluded unit is found" do
      stub_search(acceptable_movie())
      {:ok, found} = Plans.create_movie_plan(@movie)
      {:ok, found} = Plans.fetch(found.id)
      assert Plans.clean?(found)

      stub_search([])
      {:ok, gap} = Plans.create_movie_plan(%{@movie | tmdb_id: "246814"})
      {:ok, gap} = Plans.fetch(gap.id)
      refute Plans.clean?(gap)
    end
  end
end
```

- [x] **Step 2: Run**

Run: `mise exec -- mix test test/media_centaur/acquisition/reactor/handlers_test.exs`
Expected: FAIL — "automatic + clean commits" stays `ready` (the gate ignores manual plans), `clean?/1` undefined.

- [x] **Step 3: `Plans.clean?/1`**

In `lib/media_centaur/acquisition/plans.ex`, near `units_for/1`:

```elixir
  @doc """
  Whether a solved plan is clean: every wanted unit (every unit not
  excluded) was found within the plan's quality bounds — no gaps, no
  below-preference units, no pack offers. The approval gate's
  qualifying test for a manual plan with `approval_policy: "automatic"`.
  Reads the units directly so the context stays free of the board
  view-model.
  """
  @spec clean?(Plan.t()) :: boolean()
  def clean?(%Plan{id: plan_id}) do
    plan_id
    |> units_for()
    |> Enum.reject(&(&1.status == "excluded"))
    |> case do
      [] -> false
      wanted -> Enum.all?(wanted, &(&1.status == "found"))
    end
  end
```

- [x] **Step 4: The gate**

Replace `plan_changed/1`, `gate_tracking_plan/1`, `tracking_mode/1`, `approve_or_discard/1` in `lib/media_centaur/acquisition/reactor/handlers.ex` with:

```elixir
  @doc """
  The approval gate (spec 2026-09-05; ADR-056 Q3 for the tracking
  rules): when any plan finishes solving, decide its fate from the
  stamped `approval_policy` —

  * tracking plan, zero found units → delete the draft (the wants
    remain the durable intent; an automated tick that found nothing
    has no record value)
  * tracking plan whose item's mode is now `off` → discard. The one
    live read left: off is a kill switch, not a policy, so a mid-solve
    flip still wins.
  * `review` → leave it `ready`; the draft card on Downloads is the
    steering surface
  * `automatic`, tracking origin → approve when at least one unit was
    found; the want ledger retries the remainder next tick. An
    approval rejection discards (claims exclude those units next tick).
  * `automatic`, manual origin → approve only a clean plan
    (`Plans.clean?/1`); anything else stays `ready` for a person,
    because nothing retries a manual plan's remainder. An approval
    rejection (overlap, nothing to grab) also stays `ready`, logged.

  Non-ready transitions are ignored.
  """
  @spec plan_changed(PlanEvents.Changed.t()) :: :ok
  def plan_changed(%PlanEvents.Changed{status: "ready", plan_id: plan_id}) do
    case Plans.fetch(plan_id) do
      {:ok, %Plan{status: "ready"} = plan} -> gate(plan)
      _other -> :ok
    end
  end

  def plan_changed(%PlanEvents.Changed{}), do: :ok

  defp gate(%Plan{origin: "tracking"} = plan) do
    found = plan.id |> Plans.units_for() |> Enum.count(&(&1.status == "found"))

    cond do
      found == 0 -> Plans.delete_tracking_draft(plan)
      tracking_item_off?(plan) -> discard(plan)
      plan.approval_policy == "review" -> :ok
      true -> approve_or_discard(plan)
    end

    :ok
  end

  defp gate(%Plan{approval_policy: "automatic"} = plan) do
    if Plans.clean?(plan), do: approve_or_park(plan)
    :ok
  end

  defp gate(%Plan{}), do: :ok

  defp tracking_item_off?(plan) do
    case plan.tracking_item_id && ReleaseTracking.get_item(plan.tracking_item_id) do
      nil -> true
      item -> AutoGrabSettings.effective_mode(item.auto_grab_mode, AutoGrabSettings.load()) == "off"
    end
  end

  defp approve_or_discard(plan) do
    case Plans.approve(plan) do
      {:ok, committed} ->
        Log.info(:acquisition, "tracking plan auto-committed — #{committed.title}")

      {:error, reason} ->
        Log.warning(
          :acquisition,
          "tracking plan auto-approve rejected — #{plan.title} — #{inspect(reason)}"
        )

        discard(plan)
    end
  end

  defp approve_or_park(plan) do
    case Plans.approve(plan) do
      {:ok, committed} ->
        Log.info(:acquisition, "plan auto-committed — #{committed.title}")

      {:error, reason} ->
        Log.warning(
          :acquisition,
          "plan auto-approve rejected, parked for review — #{plan.title} — #{inspect(reason)}"
        )
    end
  end
```

Keep `discard/1` as it is. Update the module's top moduledoc line from "the mode gate for tracking-born plans" to "the approval gate for every plan". Note the previous behaviour ("nil item → off") is preserved: a tracking plan whose item vanished discards.

- [x] **Step 5: Run gate + existing tracking tests**

Run: `mise exec -- mix test test/media_centaur/acquisition/reactor/handlers_test.exs test/media_centaur/acquisition/drop_planner_test.exs test/media_centaur/acquisition/plans_test.exs`
Expected: PASS. If the "rejection stays ready" test fails because `create_pursuit` without a unit is not counted as a claim, add `state: "active"` and a unit via the factory's `@pursuit_unit_keys` (`season_number: nil, episode_number: nil`) — read `test/support/factory.ex:963-1060` before changing the test.

- [x] **Step 6: Commit**

```bash
git add lib/media_centaur/acquisition/reactor/handlers.ex lib/media_centaur/acquisition/plans.ex test/media_centaur/acquisition/reactor/handlers_test.exs
git commit -m "feat(acquisition): approval gate reads the stamped policy; Plans.clean?/1"
```

---

### Task 4: `Plans.count_awaiting_review/0`

Spec decision 26 (the source half; the projection is Task 8).

**Files:**
- Modify: `lib/media_centaur/acquisition/plans.ex`
- Test: `test/media_centaur/acquisition/plans_test.exs`

- [x] **Step 1: Failing test**

Append to the "approval policy stamping" describe from Task 2:

```elixir
    test "count_awaiting_review/0 counts ready drafts of any origin" do
      assert Plans.count_awaiting_review() == 0

      # Nothing found → the movie plan solves to ready with a gap.
      {:ok, _plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})
      assert Plans.count_awaiting_review() == 1

      {:ok, ready} = Plans.create_movie_plan(%{tmdb_id: "246814", title: "Sample Movie", year: 2006})
      {:ok, ready} = Plans.fetch(ready.id)
      {:ok, _discarded} = Plans.discard(ready)
      assert Plans.count_awaiting_review() == 1
    end
```

- [x] **Step 2: Run** — Expected: FAIL, undefined function.

- [x] **Step 3: Implement** (below `list_drafts/0`):

```elixir
  @doc """
  How many plans are waiting on a person: status `ready`, any origin.
  The Incoming follow-up pill's source (`MediaCentaurWeb.ShellBadges`).
  """
  @spec count_awaiting_review() :: non_neg_integer()
  def count_awaiting_review do
    Plan
    |> where([p], p.status == "ready")
    |> Repo.aggregate(:count)
  end
```

- [x] **Step 4: Run** — Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/plans.ex test/media_centaur/acquisition/plans_test.exs
git commit -m "feat(acquisition): Plans.count_awaiting_review/0"
```

---

### Task 5: `Plans.DownloadScope` — pure unit selection

Spec decisions 8, 9.

**Files:**
- Create: `lib/media_centaur/acquisition/plans/download_scope.ex`
- Create: `test/media_centaur/acquisition/plans/download_scope_test.exs`

- [x] **Step 1: Failing test**

```elixir
defmodule MediaCentaur.Acquisition.Plans.DownloadScopeTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Plans.DownloadScope
  alias MediaCentaur.Acquisition.Targeting

  defp episode(season, number, opts \\ []) do
    %Targeting.Episode{
      season_number: season,
      episode_number: number,
      label: "S#{season}E#{number}",
      aired?: Keyword.get(opts, :aired?, true),
      in_library?: Keyword.get(opts, :in_library?, false),
      tracked?: Keyword.get(opts, :tracked?, false)
    }
  end

  defp selection(seasons) do
    %Targeting.Selection{tmdb_id: "42", title: "Sample Show", tracked?: false, seasons: seasons}
  end

  test "first_season is the lowest numbered season ≥ 1 with a pickable episode, specials skipped" do
    selection =
      selection([
        %Targeting.Season{season_number: 0, episodes: [episode(0, 1)]},
        %Targeting.Season{season_number: 1, episodes: [episode(1, 1, in_library?: true), episode(1, 2)]},
        %Targeting.Season{season_number: 2, episodes: [episode(2, 1)]}
      ])

    assert DownloadScope.units(selection, :first_season) == [{1, 2}]
  end

  test "first_season moves past a season with nothing pickable" do
    selection =
      selection([
        %Targeting.Season{season_number: 1, episodes: [episode(1, 1, tracked?: true)]},
        %Targeting.Season{season_number: 2, episodes: [episode(2, 1), episode(2, 2, aired?: false)]}
      ])

    assert DownloadScope.units(selection, :first_season) == [{2, 1}]
  end

  test "everything is the picker default: all aired, not in library, not tracked" do
    selection =
      selection([
        %Targeting.Season{season_number: 0, episodes: [episode(0, 1)]},
        %Targeting.Season{season_number: 1, episodes: [episode(1, 1), episode(1, 2, in_library?: true)]},
        %Targeting.Season{season_number: 2, episodes: [episode(2, 1), episode(2, 2, aired?: false)]}
      ])

    assert DownloadScope.units(selection, :everything) == [{0, 1}, {1, 1}, {2, 1}]
  end

  test "an empty universe yields no units for either scope" do
    assert DownloadScope.units(selection([]), :first_season) == []
    assert DownloadScope.units(selection([]), :everything) == []
  end
end
```

Note the third test: `Targeting.default_units/1` includes season 0 when it has pickable aired episodes. The spec excludes specials from `first_season` only; `everything` keeps the picker default exactly, so a downloaded-everything series matches what approving the picker's default would fetch.

- [x] **Step 2: Run** — Expected: FAIL, module undefined.

- [x] **Step 3: Implement**

```elixir
defmodule MediaCentaur.Acquisition.Plans.DownloadScope do
  @moduledoc """
  What a one-click download of a series covers (spec 2026-09-05 §8–9),
  as `{season, episode}` units over a `Targeting.Selection`:

  * `:first_season` — the lowest season numbered 1 or higher that has at
    least one pickable episode (aired, not in the library, not tracked),
    and exactly those episodes of that season. Specials (season 0) are
    never part of it.
  * `:everything` — the picker's default (`Targeting.default_units/1`):
    every pickable episode, specials included.

  Pure; the caller (`Plans.plan_title/2`) owns the TMDB fetch, the
  plan creation and, for `:everything`, the tracking hand-off.
  """

  alias MediaCentaur.Acquisition.Targeting

  @type scope :: :first_season | :everything

  @spec units(Targeting.Selection.t(), scope()) :: [{pos_integer(), pos_integer()}]
  def units(%Targeting.Selection{} = selection, :everything), do: Targeting.default_units(selection)

  def units(%Targeting.Selection{} = selection, :first_season) do
    selection
    |> Targeting.default_units()
    |> Enum.reject(fn {season, _episode} -> season < 1 end)
    |> Enum.group_by(fn {season, _episode} -> season end)
    |> Enum.min_by(fn {season, _units} -> season end, fn -> {nil, []} end)
    |> elem(1)
  end
end
```

- [x] **Step 4: Run** — Expected: PASS (4 tests).

- [x] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/plans/download_scope.ex test/media_centaur/acquisition/plans/download_scope_test.exs
git commit -m "feat(acquisition): DownloadScope — first-season and everything unit selection"
```

---

### Task 6: `Plans.plan_title/2`

Spec decisions 9, 17, 19 (amended: one asynchronous contract for both media types; the policy is an explicit option, so the context knows nothing about clicks).

**Files:**
- Modify: `lib/media_centaur/acquisition/plans.ex`
- Modify: `test/support/tmdb_stubs.ex` (`stub_series_universe_for_targeting/0`)
- Test: `test/media_centaur/acquisition/plans_test.exs`

- [x] **Step 1: The shared TMDB fixture**

Add to `test/support/tmdb_stubs.ex` a `stub_series_universe_for_targeting/0` that makes `Targeting.series_selection("246810")` return season 1 with episodes 1–3 aired and season 2 with episode 1 aired, none in the library. Read `test/media_centaur/acquisition/targeting_test.exs` for the exact `get_tv` + per-season payload shape and move that builder here (one fixture, callers in this task and Task 13; update `targeting_test.exs` to call it too so the builder is not duplicated).

- [x] **Step 2: Failing tests**

Append a describe to `test/media_centaur/acquisition/plans_test.exs`:

```elixir
  describe "plan_title/2" do
    import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

    alias MediaCentaur.ReleaseTracking
    alias MediaCentaur.TMDB.Title

    setup do
      MediaCentaur.TmdbStubs.setup_tmdb_client()
      :ok
    end

    defp movie_title do
      Title.new!(%{tmdb_id: 246_813, media_type: :movie, name: "Sample Movie", year: "2005"})
    end

    defp show_title do
      Title.new!(%{tmdb_id: 246_810, media_type: :tv_series, name: "Sample Show", year: "2010"})
    end

    test "a movie plans with the given policy" do
      assert :ok = Plans.plan_title(movie_title(), approval_policy: "automatic")
      await_supervised_tasks()

      [plan] = Plans.list_drafts()
      assert plan.tmdb_type == "movie"
      assert plan.tmdb_id == "246813"
      assert plan.year == 2005
      assert plan.approval_policy == "automatic"
      assert plan.origin == "manual"
    end

    test "the policy defaults to review" do
      assert :ok = Plans.plan_title(movie_title())
      await_supervised_tasks()

      assert [%{approval_policy: "review"}] = Plans.list_drafts()
    end

    test "a series with :first_season plans season 1's pickable episodes, no tracking" do
      MediaCentaur.TmdbStubs.stub_series_universe_for_targeting()

      assert :ok = Plans.plan_title(show_title(), scope: :first_season, approval_policy: "automatic")
      await_supervised_tasks()

      [plan] = Plans.list_drafts()
      assert plan.approval_policy == "automatic"
      assert Enum.map(Plans.units_for(plan.id), &{&1.season_number, &1.episode_number}) == [{1, 1}, {1, 2}, {1, 3}]
      assert ReleaseTracking.get_item_by_tmdb(246_810, :tv_series) == nil
    end

    test "a series with :everything plans every pickable episode, then tracks the title" do
      MediaCentaur.TmdbStubs.stub_series_universe_for_targeting()

      assert :ok = Plans.plan_title(show_title(), scope: :everything)
      await_supervised_tasks()

      [plan] = Plans.list_drafts()
      assert length(Plans.units_for(plan.id)) == 4
      assert %ReleaseTracking.Item{} = ReleaseTracking.get_item_by_tmdb(246_810, :tv_series)
    end

    test "a series that is already tracked is not tracked twice" do
      MediaCentaur.TmdbStubs.stub_series_universe_for_targeting()
      create_tracking_item(%{tmdb_id: 246_810, media_type: :tv_series, name: "Sample Show"})

      assert :ok = Plans.plan_title(show_title(), scope: :everything)
      await_supervised_tasks()

      assert [_plan] = Plans.list_drafts()
      assert length(Repo.all(ReleaseTracking.Item)) == 1
    end

    test "a TMDB failure leaves no plan" do
      Req.Test.stub(:tmdb, fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

      assert :ok = Plans.plan_title(show_title(), scope: :first_season)
      await_supervised_tasks()

      assert Plans.list_drafts() == []
    end
  end
```

- [x] **Step 3: Run** — Expected: FAIL, `plan_title/2` undefined.

- [x] **Step 4: Implement**

In `lib/media_centaur/acquisition/plans.ex` add aliases `MediaCentaur.Acquisition.Plans.DownloadScope`, `MediaCentaur.TMDB.Title`, and `require MediaCentaur.Log, as: Log` if not present. Then:

```elixir
  @doc """
  Plans a TMDB title from its snapshot alone (spec 2026-09-05 §17): the
  door a surface that lists titles the library does not own uses, where
  there is no picker. Runs on the context task supervisor — a series
  needs a targeting fetch, and the work must outlive the calling
  LiveView (ADR-049) — and returns as soon as it is queued; the plan row
  broadcasts on `acquisition:updates` when it exists. Movies take the
  same path so the contract is one shape.

  Options: `approval_policy:` (`"automatic"` | `"review"`, default
  review — the one-click download passes automatic); `scope:` (series
  only) `:first_season` (default) or `:everything`, see `DownloadScope`.
  `:everything` also starts release tracking for the title so new
  episodes follow; an already-tracked title is left alone. The plan is
  created before tracking so its units are not excluded as tracked.

  A failure inside the task (TMDB unreachable, nothing pickable) is
  logged at warning on `:acquisition` and leaves no plan.
  """
  @spec plan_title(Title.t(), keyword()) :: :ok
  def plan_title(%Title{} = title, opts \ []) do
    policy = Keyword.get(opts, :approval_policy, "review")
    scope = Keyword.get(opts, :scope, :first_season)

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      do_plan_title(title, policy, scope)
    end)

    :ok
  end

  defp do_plan_title(%Title{media_type: :movie} = title, policy, _scope) do
    case create_movie_plan(
           %{tmdb_id: title.tmdb_id, title: title.name, year: title_year(title)},
           approval_policy: policy
         ) do
      {:ok, _plan} -> :ok
      {:error, reason} -> Log.warning(:acquisition, "could not plan — #{title.name} — #{inspect(reason)}")
    end
  end

  defp do_plan_title(%Title{media_type: :tv_series} = title, policy, scope) do
    with {:ok, selection} <- Targeting.series_selection(title.tmdb_id),
         units when units != [] <- DownloadScope.units(selection, scope),
         {:ok, _plan} <- create_series_plan(selection, units, approval_policy: policy) do
      if scope == :everything, do: ensure_tracked(title)
      :ok
    else
      [] ->
        Log.warning(:acquisition, "nothing to plan — #{title.name}")

      {:error, reason} ->
        Log.warning(:acquisition, "could not plan — #{title.name} — #{inspect(reason)}")
    end
  end

  defp ensure_tracked(%Title{} = title) do
    case ReleaseTracking.get_item_by_tmdb(title.tmdb_id, :tv_series) do
      nil -> ReleaseTracking.track_from_search(title)
      _item -> :ok
    end
  end

  defp title_year(%Title{year: year}) when is_binary(year) do
    case Integer.parse(year) do
      {parsed, ""} -> parsed
      _other -> nil
    end
  end

  defp title_year(_title), do: nil
```

`Plans` may need `Targeting` and `ReleaseTracking` aliases; both are already used elsewhere in the file. If `mix compile` reports a Boundary violation, the dep is missing from `Acquisition`'s `use Boundary, deps: [...]` in `lib/media_centaur/acquisition.ex` — add it there, not with an exception.

- [x] **Step 5: Run**

Run: `mise exec -- mix test test/media_centaur/acquisition/plans_test.exs test/media_centaur/acquisition/targeting_test.exs`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add lib/media_centaur/acquisition/plans.ex test/media_centaur/acquisition/plans_test.exs test/media_centaur/acquisition/targeting_test.exs test/support/tmdb_stubs.ex
git commit -m "feat(acquisition): Plans.plan_title/2 — plan a title from its snapshot"
```

---

### Task 7: `Acquisition.TitleStates` — acquisition state per title

Spec decision 20 (amended: batched by refs, one query per load).

**Files:**
- Create: `lib/media_centaur/acquisition/title_states.ex`
- Create: `test/media_centaur/acquisition/title_states_test.exs`

- [x] **Step 1: Failing test**

```elixir
defmodule MediaCentaur.Acquisition.TitleStatesTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.{Plans, TitleStates}

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
    )

    :ok
  end

  test "empty input, empty output" do
    assert TitleStates.for_refs([]) == %{}
  end

  test "a ready draft is needs_review, an in-flight pursuit is downloading, nothing is absent" do
    {:ok, _plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2005})
    create_pursuit(%{tmdb_id: "778", tmdb_type: "movie", title: "Sample Movie B"})

    assert TitleStates.for_refs([{777, :movie}, {778, :movie}, {779, :movie}, {42, :tv_series}]) == %{
             {777, :movie} => :needs_review,
             {778, :movie} => :downloading
           }
  end

  test "a pursuit outranks a draft for the same title" do
    {:ok, _plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2005})
    create_pursuit(%{tmdb_id: "777", tmdb_type: "movie", title: "Sample Movie"})

    assert TitleStates.for_refs([{777, :movie}]) == %{{777, :movie} => :downloading}
  end

  test "a planning draft is planning" do
    {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2005})
    force_state(plan, "planning")

    assert TitleStates.for_refs([{777, :movie}]) == %{{777, :movie} => :planning}
  end
end
```

If `force_state/2` does not accept a `Plan`, read `test/support/factory.ex` for `force_attrs/2` and use `force_attrs(plan, %{status: "planning"})`.

- [x] **Step 2: Run** — Expected: FAIL, module undefined.

- [x] **Step 3: Implement**

```elixir
defmodule MediaCentaur.Acquisition.TitleStates do
  @moduledoc """
  The acquisition state of a TMDB title, for surfaces that list titles
  the library does not own yet (Discovery rows and the title detail
  modal; spec 2026-09-05 §20):

  * `:downloading` — a pursuit for the title is in flight
  * `:needs_review` — a draft plan is `ready`, waiting on a person
  * `:planning` — a draft plan is solving

  A pursuit outranks a draft. Titles with nothing in flight are absent
  from the result. One query per table for the whole list, keyed by
  `{tmdb_id, media_type}` the way `Library.ExternalIds.tmdb_owners/1`
  keys library presence.
  """

  import Ecto.Query

  alias MediaCentaur.Acquisition.Plans.Plan
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, State}
  alias MediaCentaur.Repo

  @type ref :: {integer(), :movie | :tv_series}
  @type state :: :downloading | :needs_review | :planning

  @spec for_refs([ref()]) :: %{ref() => state()}
  def for_refs([]), do: %{}

  def for_refs(refs) when is_list(refs) do
    ids = refs |> Enum.map(fn {tmdb_id, _type} -> to_string(tmdb_id) end) |> Enum.uniq()

    drafts =
      Plan
      |> where([p], p.status in ["planning", "ready"] and p.tmdb_id in ^ids)
      |> select([p], {p.tmdb_id, p.tmdb_type, p.status})
      |> Repo.all()
      |> Map.new(fn {tmdb_id, tmdb_type, status} ->
        {ref(tmdb_id, tmdb_type), draft_state(status)}
      end)

    pursuits =
      Pursuit
      |> where([p], p.state in ^State.in_flight() and p.tmdb_id in ^ids)
      |> select([p], {p.tmdb_id, p.tmdb_type})
      |> Repo.all()
      |> Map.new(fn {tmdb_id, tmdb_type} -> {ref(tmdb_id, tmdb_type), :downloading} end)

    wanted = MapSet.new(refs)

    drafts
    |> Map.merge(pursuits)
    |> Map.filter(fn {ref, _state} -> MapSet.member?(wanted, ref) end)
  end

  defp draft_state("ready"), do: :needs_review
  defp draft_state("planning"), do: :planning

  defp ref(tmdb_id, "movie"), do: {String.to_integer(tmdb_id), :movie}
  defp ref(tmdb_id, "tv"), do: {String.to_integer(tmdb_id), :tv_series}
end
```

A pursuit created without a tmdb_type of `"movie"`/`"tv"` (legacy `prowlarr_query` recipes have `tmdb_id: nil`) never matches `p.tmdb_id in ^ids`, so `ref/2` only sees the two literal types.

- [x] **Step 4: Run** — Expected: PASS (4 tests).

- [x] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/title_states.ex test/media_centaur/acquisition/title_states_test.exs
git commit -m "feat(acquisition): TitleStates — per-title acquisition state for discovery surfaces"
```

---

### Task 8: `ShellBadges.Counts` and the Incoming source

Spec decisions 23, 26.

**Files:**
- Modify: `lib/media_centaur_web/shell_badges.ex`
- Test: `test/media_centaur_web/shell_badges_test.exs`

- [x] **Step 1: Failing tests**

In `test/media_centaur_web/shell_badges_test.exs` add to the "counts projection" describe:

```elixir
    test "counts/0 returns a Counts struct carrying plans_awaiting_review" do
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Settings.Config, :config},
        config
        |> Map.put(:prowlarr_url, "http://prowlarr.test")
        |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
      )

      {:ok, _plan} =
        MediaCentaur.Acquisition.Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2005})

      assert %ShellBadges.Counts{plans_awaiting_review: 1} = ShellBadges.counts()
    end

    test "relevant?/1 accepts a plan status change" do
      assert ShellBadges.relevant?(%MediaCentaur.Acquisition.PlanEvents.Changed{plan_id: "id", status: "ready"})
    end
```

Change the existing assertions in that file from map access to struct access where they read `counts.review_pending` — struct field access has the same syntax, so most lines need no change; `assert is_integer(counts.diagnostics_unseen)` stays.

- [x] **Step 2: Run** — Expected: FAIL (`ShellBadges.Counts` undefined; `relevant?` false).

- [x] **Step 3: Implement**

In `lib/media_centaur_web/shell_badges.ex`:

Add a nested struct after the moduledoc:

```elixir
  defmodule Counts do
    @moduledoc """
    The sidebar's badge counts — the one value `Layouts.app` takes as
    `badges`. Two idioms and nothing else (UIDR-030):

    * **Follow-up pills** — items on that page waiting on a decision from
      the user; persist until handled. `plans_awaiting_review` (Incoming),
      `review_pending + mapping_pending` (Review), `diagnostics_unseen`
      (Status).
    * **Condition dot** — something is wrong right now; persists until
      resolved. `status_errors` (Status).
    """

    defstruct diagnostics_unseen: 0,
              review_pending: 0,
              mapping_pending: 0,
              status_errors: 0,
              plans_awaiting_review: 0

    @type t :: %__MODULE__{
            diagnostics_unseen: non_neg_integer(),
            review_pending: non_neg_integer(),
            mapping_pending: non_neg_integer(),
            status_errors: non_neg_integer(),
            plans_awaiting_review: non_neg_integer()
          }
  end
```

Rewrite the moduledoc's opening to name the two idioms (copy the `Counts` wording) and add the fifth bullet:

```
    * `:plans_awaiting_review` — draft plans in `ready`, waiting on a
      person's approval (`Acquisition.Plans.count_awaiting_review/0`).
      Drives the Incoming follow-up pill.
```

Aliases: add `alias MediaCentaur.Acquisition.PlanEvents` and `alias MediaCentaur.Acquisition.Plans`.

`subscribe/0`: add `Topics.subscribe(Topics.acquisition_updates())`.

`relevant?/1`: add `def relevant?(%PlanEvents.Changed{}), do: true` before the catch-all.

`counts/0` spec becomes `@spec counts() :: Counts.t()`; `compute_counts/0` returns:

```elixir
    %Counts{
      diagnostics_unseen: DiagnosticsBadge.count(),
      review_pending: Review.count_pending(),
      mapping_pending: Reconciliation.count_awaiting(),
      status_errors: HealthBoard.tile_state(ErrorReports.list_buckets()).error_count,
      plans_awaiting_review: Plans.count_awaiting_review()
    }
```

`assign_counts/1` assigns one key instead of four:

```elixir
  defp assign_counts(socket), do: assign(socket, :badges, counts())
```

The on_mount hook must also subscribe the LiveView to `acquisition:updates` for the immediate re-read, mirroring the review topics — **but** `IncomingLive` and `DiscoveryLive` (after Task 13) subscribe to that topic themselves via `Acquisition.subscribe/0`. Do NOT subscribe here; the projection's derived `{:shell_badges_updated}` broadcast is the delivery path for the plan count (the worker refreshes on `PlanEvents.Changed`). Document this in the hook's moduledoc section: "Plan changes reach the sidebar through the derived broadcast only; pages that need the source event subscribe themselves."

`refresh/2`: unchanged clauses (they call `assign_counts/1`).

- [x] **Step 4: Run**

Run: `mise exec -- mix test test/media_centaur_web/shell_badges_test.exs`
Expected: PASS. Compilation will now fail elsewhere (`Layouts.app` still expects four attrs and every page still passes them). Task 9 fixes that; do not commit a broken build — continue straight into Task 9 and commit both together.

---

### Task 9: `follow_up_pill` component, `Layouts.app` `badges` attr, the three entries

Spec decisions 23, 24, 25 (amended: the pill anchors to the icon corner in the collapsed rail and sits at the row's end when expanded, via one CSS rule keyed off `--sidebar-expanded`; the Status condition dot moves to the icon's bottom-right so the two never overlap).

**Files:**
- Create: `lib/media_centaur_web/components/follow_up_pill.ex`
- Create: `storybook/navigation/follow_up_pill.story.exs`
- Modify: `lib/media_centaur_web/components/layouts.ex`
- Modify: `assets/css/app.css`
- Modify: every `render/1` passing `diagnostics_unseen=`/`status_errors=`/`review_pending=`/`mapping_pending=` to `Layouts.app` (11 files — `grep -rln "review_pending={" lib`)
- Test: `test/media_centaur_web/review_badge_test.exs`, `test/media_centaur_web/diagnostics_badge_test.exs`, new `test/media_centaur_web/incoming_badge_test.exs`

- [x] **Step 1: Failing test — Incoming pill**

```elixir
defmodule MediaCentaurWeb.IncomingBadgeTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Acquisition.Plans

  @incoming_pill ~s{aside a[data-tip="Incoming"] [data-component="follow-up-pill"]}

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
    )

    :ok
  end

  test "no pill when nothing awaits review", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/history")
    refute has_element?(view, @incoming_pill)
  end

  test "a ready draft shows the count; approving it clears the pill", %{conn: conn} do
    {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2005})

    {:ok, view, _html} = live(conn, ~p"/history")
    assert has_element?(view, @incoming_pill, "1")

    {:ok, plan} = Plans.fetch(plan.id)
    {:ok, _discarded} = Plans.discard(plan)
    # The worker is not running under ExUnit; deliver the derived broadcast by hand.
    :ok = MediaCentaurWeb.ShellBadges.refresh_cache()

    refute has_element?(view, @incoming_pill)
  end
end
```

Also update `test/media_centaur_web/review_badge_test.exs` and `test/media_centaur_web/diagnostics_badge_test.exs`: wherever they assert on the count badge element, target `[data-component="follow-up-pill"]` inside the entry. Read both files fully first; keep every existing assertion's meaning.

- [x] **Step 2: Run** — Expected: FAIL (compile error from Task 8 first, then missing pill).

- [x] **Step 3: The component**

`lib/media_centaur_web/components/follow_up_pill.ex`:

```elixir
defmodule MediaCentaurWeb.Components.FollowUpPill do
  @moduledoc """
  The sidebar follow-up pill (UIDR-030): a count of items on that page
  waiting on a decision from the user. One variant, one size, one
  placement rule. Renders nothing at zero — silence is the healthy
  state. It persists until the items are handled, and each source
  defines handling: approve or discard a plan, review a file, look at
  an incident (the Status source's seen-marker is its definition).

  Placement is one CSS rule (`.sidebar-follow-up`) keyed off the rail's
  `--sidebar-expanded` switch: at the row's end when the rail is open,
  at the icon's top-right corner when it is the 52px rail, so the count
  survives both widths. The condition dot sits at the icon's
  bottom-right so the two never overlap.
  """

  use Phoenix.Component

  attr :count, :integer, required: true, doc: "items waiting on a decision; 0 renders nothing"
  attr :id, :string, required: true

  def follow_up_pill(assigns) do
    ~H"""
    <span
      :if={@count > 0}
      id={@id}
      class="sidebar-follow-up badge badge-error badge-xs"
      data-component="follow-up-pill"
      aria-label={"#{@count} waiting for you"}
    >
      {@count}
    </span>
    """
  end
end
```

`MC0006`/RawBadgeClass flags raw `class="badge …"` outside `core_components.ex`. Use the component instead:

```elixir
  import MediaCentaurWeb.CoreComponents, only: [badge: 1]
  ...
    <.badge
      :if={@count > 0}
      id={@id}
      variant="error"
      size="xs"
      class="sidebar-follow-up"
      data-component="follow-up-pill"
      aria-label={"#{@count} waiting for you"}
    >
      {@count}
    </.badge>
```

- [x] **Step 4: CSS**

In `assets/css/app.css` after the `.sidebar-label` rule:

```css
/* Follow-up pill (UIDR-030) — one element, two placements. Expanded rail:
   in flow at the row's end. 52px rail: anchored to the icon's top-right
   corner so the count survives the label's fade. `--sidebar-expanded`
   drives the switch, like every other expanded-state property. */
.sidebar-follow-up {
  position: absolute;
  right: calc(0.5rem + 0.25rem * var(--sidebar-expanded));
  top: calc(0.125rem + (50% - 0.125rem) * var(--sidebar-expanded));
  transform: translateY(calc(-50% * var(--sidebar-expanded)));
  transition: top 0.25s ease, right 0.25s ease, transform 0.25s ease;
}
```

`.sidebar-link` already has `position: relative`. Verify visually in Step 9.

- [x] **Step 5: `Layouts.app`**

Replace the four count attrs with one:

```elixir
  attr :badges, MediaCentaurWeb.ShellBadges.Counts,
    default: %MediaCentaurWeb.ShellBadges.Counts{},
    doc: """
    The sidebar's badge counts, seeded app-wide by `MediaCentaurWeb.ShellBadges`
    (default `live_session` on_mount) and live-refreshed via the `shell:badges`
    derived topic. See `ShellBadges.Counts` for the two idioms — follow-up
    pills and the condition dot.
    """
```

Alias `MediaCentaurWeb.Components.FollowUpPill` and import `follow_up_pill/1`. Then:

Incoming entry — after the label span:

```heex
            <FollowUpPill.follow_up_pill id="sidebar-incoming-follow-up" count={@badges.plans_awaiting_review} />
```

Status entry — the icon wrapper keeps the dot but moves it:

```heex
            <span class="relative inline-flex flex-shrink-0">
              <.icon name="hero-squares-2x2" class="size-5" />
              <span
                :if={@badges.status_errors > 0}
                id="sidebar-status-error-dot"
                class="absolute -bottom-0.5 -right-0.5 size-2 rounded-full bg-error"
                aria-hidden="true"
              />
            </span>
            <span class="sidebar-label">Status</span>
            <FollowUpPill.follow_up_pill id="sidebar-status-follow-up" count={@badges.diagnostics_unseen} />
```

Review entry — the `:if` and `navigate` read `@badges.review_pending` / `@badges.mapping_pending`; replace the primary badge with:

```heex
            <FollowUpPill.follow_up_pill
              id="sidebar-review-follow-up"
              count={@badges.review_pending + @badges.mapping_pending}
            />
```

Remove the now-unused `.badge` calls from the sidebar.

- [x] **Step 6: Every page's render**

For each of the 11 files from `grep -rln "review_pending={" lib`, replace the four lines

```heex
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
      status_errors={assigns[:status_errors] || 0}
      review_pending={assigns[:review_pending] || 0}
      mapping_pending={assigns[:mapping_pending] || 0}
```

with

```heex
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
```

Pages outside the default `live_session` (setup) have no `:badges` assign; the fallback keeps them rendering. Grep for any other reader of the four assigns (`grep -rn "diagnostics_unseen\|status_errors\|review_pending\|mapping_pending" lib test storybook`) and update it — including the layouts story under `storybook/navigation/` if it passes those attrs.

- [x] **Step 7: Story**

`storybook/navigation/follow_up_pill.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Navigation.FollowUpPill do
  @moduledoc """
  The sidebar follow-up pill (UIDR-030) — a count of items waiting on the
  user, one variant for every entry that has a source. Zero renders
  nothing. The two rail placements are a CSS switch on the rail itself,
  so this story shows the element; verify placement on the live sidebar.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.FollowUpPill.follow_up_pill/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :one,
        description: "One item waiting.",
        attributes: %{id: "pill-one", count: 1}
      },
      %Variation{
        id: :many,
        description: "A larger count keeps the same size; the pill widens.",
        attributes: %{id: "pill-many", count: 12}
      },
      %Variation{
        id: :zero,
        description: "Nothing waiting renders nothing — silence is the healthy state.",
        attributes: %{id: "pill-zero", count: 0}
      }
    ]
  end
end
```

- [x] **Step 8: Compile, assets, tests**

Run: `mise exec -- mix compile --warnings-as-errors && mise exec -- mix assets.build && mise exec -- mix test test/media_centaur_web/incoming_badge_test.exs test/media_centaur_web/review_badge_test.exs test/media_centaur_web/diagnostics_badge_test.exs test/media_centaur_web/shell_badges_test.exs test/media_centaur_web/page_smoke_test.exs test/storybook_compile_test.exs test/storybook_render_test.exs`
Expected: PASS.

- [x] **Step 9: Real-browser check**

Restart the dev service (`systemctl --user restart media-centaur-dev`), then:

```
page-shot --url http://127.0.0.1:2160/history --viewport 1920x1080 --wait-ms 3000
```

Read the PNG: with the rail collapsed the Incoming/Review/Status pills (if any count is non-zero on the dev DB) sit at the icon's top-right corner and the Status dot, if lit, at the bottom-right. Hover-expand is not capturable headless; verify the expanded placement by evaluating the computed `right`/`top` of `.sidebar-follow-up` with `chromium-probe` after setting `document.documentElement.setAttribute("data-sidebar-hover","")`. If a count is zero on the dev DB, create a ready draft through the Incoming picker in the browser, check, then discard it.

- [x] **Step 10: Commit (Tasks 8 + 9 together)**

```bash
git add lib/media_centaur_web/shell_badges.ex lib/media_centaur_web/components/follow_up_pill.ex lib/media_centaur_web/components/layouts.ex assets/css/app.css storybook/navigation/follow_up_pill.story.exs test/media_centaur_web/ lib/media_centaur_web/live
git commit -m "feat(shell): follow-up pill — one badge idiom for Incoming, Review, Status"
```

---

### Task 10: `TitleDetail` view-model and `DiscoveryLive.Logic`

Spec decisions 12, 13, 21.

**Files:**
- Create: `lib/media_centaur_web/components/discovery/title_detail.ex`
- Create: `lib/media_centaur_web/live/discovery_live/logic.ex`
- Create: `test/media_centaur_web/live/discovery_live/logic_test.exs`

- [x] **Step 1: Failing tests**

```elixir
defmodule MediaCentaurWeb.DiscoveryLive.LogicTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.TitleDetail
  alias MediaCentaurWeb.DiscoveryLive.Logic

  @today ~D[2026-09-05]

  defp movie(overrides \\ %{}) do
    Title.new!(
      Map.merge(
        %{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2010", release_date: ~D[2010-03-05]},
        overrides
      )
    )
  end

  defp facts(overrides \\ %{}) do
    Map.merge(
      %{
        library_owner_id: nil,
        on_watchlist?: false,
        acquisition_state: nil,
        release_mode_available: true,
        today: @today
      },
      overrides
    )
  end

  describe "title_detail/2 primary action" do
    test "in library wins over everything" do
      detail = Logic.title_detail(movie(), facts(%{library_owner_id: "owner", acquisition_state: :downloading}))
      assert detail.primary == {:in_library, "owner"}
    end

    test "downloading, needs review and planning are states, not actions" do
      assert Logic.title_detail(movie(), facts(%{acquisition_state: :downloading})).primary == {:state, :downloading}
      assert Logic.title_detail(movie(), facts(%{acquisition_state: :needs_review})).primary == {:state, :needs_review}
      assert Logic.title_detail(movie(), facts(%{acquisition_state: :planning})).primary == {:state, :planning}
    end

    test "released with an indexer downloads; a series carries the scope menu" do
      assert Logic.title_detail(movie(), facts()).primary == :download

      show = Title.new!(%{tmdb_id: 42, media_type: :tv_series, name: "Sample Show", release_date: ~D[2010-01-01]})
      detail = Logic.title_detail(show, facts())
      assert detail.primary == :download
      assert detail.scoped?
    end

    test "upcoming, or no indexer, tracks the release" do
      assert Logic.title_detail(movie(%{release_date: ~D[2999-01-01]}), facts()).primary == :track
      assert Logic.title_detail(movie(), facts(%{release_mode_available: false})).primary == :track
    end
  end

  describe "title_detail/2 secondary and provenance" do
    test "add to watchlist flips to on watchlist" do
      refute Logic.title_detail(movie(), facts()).on_watchlist?
      assert Logic.title_detail(movie(), facts(%{on_watchlist?: true})).on_watchlist?
    end

    test "carries the feed provenance when given" do
      detail =
        Logic.title_detail(
          movie(),
          facts(%{sender: "Sample Friend", note: "Watch it", recommended_at: ~U[2026-09-01 10:00:00Z], own?: false})
        )

      assert %TitleDetail{sender: "Sample Friend", note: "Watch it", own?: false} = detail
    end
  end

  describe "acquisition_marker/1" do
    test "words for each state, nil for none" do
      assert Logic.acquisition_marker(:planning) == "Planning"
      assert Logic.acquisition_marker(:downloading) == "Downloading"
      assert Logic.acquisition_marker(:needs_review) == "Needs review"
      assert Logic.acquisition_marker(nil) == nil
    end
  end

  describe "parse_title_ref/1" do
    test "the URL param round-trips" do
      assert Logic.parse_title_ref("movie-777") == {:ok, {777, :movie}}
      assert Logic.parse_title_ref("tv_series-42") == {:ok, {42, :tv_series}}
      assert Logic.parse_title_ref("book-1") == :error
      assert Logic.parse_title_ref("movie-x") == :error
      assert Logic.title_ref_param({777, :movie}) == "movie-777"
    end
  end
end
```

- [x] **Step 2: Run** — Expected: FAIL, modules undefined.

- [x] **Step 3: The struct**

`lib/media_centaur_web/components/discovery/title_detail.ex`:

```elixir
defmodule MediaCentaurWeb.Components.Discovery.TitleDetail do
  @moduledoc """
  The title detail modal's view-model (spec 2026-09-05 §12–13): one
  TMDB title the library does not own, with the facts the modal's
  actions depend on already decided. Built by `DiscoveryLive.Logic.
  title_detail/2`; rendered by `TitleDetailModal`.

  `primary` is the one honest primary action for the title's state:
  `{:in_library, owner_id}` (links to the library detail), `{:state,
  acquisition_state}` (Planning / Downloading / Needs review — a fact,
  not a verb), `:download`, or `:track`. `scoped?` says the download
  carries the series scope menu. `sender`, `note`, `recommended_at` and
  `own?` are the feed provenance and nil on a watchlist-born detail
  without one; `sender` is nil on an own recommendation (the modal
  reads `own?`).
  """

  alias MediaCentaur.TMDB.Title

  @enforce_keys [:ref, :title, :primary, :scoped?, :on_watchlist?]
  defstruct [
    :ref,
    :title,
    :poster_url,
    :backdrop_url,
    :primary,
    :scoped?,
    :on_watchlist?,
    :sender,
    :note,
    :recommended_at,
    :own?,
    :recommendation_id
  ]

  @type primary ::
          {:in_library, Ecto.UUID.t()}
          | {:state, :planning | :downloading | :needs_review}
          | :download
          | :track

  @type t :: %__MODULE__{
          ref: {integer(), Title.media_type()},
          title: Title.t(),
          poster_url: String.t() | nil,
          backdrop_url: String.t() | nil,
          primary: primary(),
          scoped?: boolean(),
          on_watchlist?: boolean(),
          sender: String.t() | nil,
          note: String.t() | nil,
          recommended_at: DateTime.t() | nil,
          own?: boolean() | nil,
          recommendation_id: Ecto.UUID.t() | nil
        }
end
```

- [x] **Step 4: The logic**

`lib/media_centaur_web/live/discovery_live/logic.ex`:

```elixir
defmodule MediaCentaurWeb.DiscoveryLive.Logic do
  @moduledoc """
  Pure decisions for the Discovery page (ADR-030): the title detail
  view-model, the acquisition-state words the rows and the modal show,
  and the `?title=` URL param's shape.
  """

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Acquisition.MediaResults
  alias MediaCentaurWeb.Components.Discovery.TitleDetail

  @type acquisition_state :: :planning | :downloading | :needs_review | nil

  @doc """
  Builds the detail for a title from the facts the host resolved:
  `library_owner_id`, `on_watchlist?`, `acquisition_state`,
  `release_mode_available`, `today`, plus optional `poster_url`,
  `backdrop_url`, `sender`, `note`, `recommended_at`, `own?`,
  `recommendation_id`. The primary action is the
  watchlist row's three-state rule with the acquisition state folded in
  between In library and Download.
  """
  @spec title_detail(Title.t(), map()) :: TitleDetail.t()
  def title_detail(%Title{} = title, facts) do
    %TitleDetail{
      ref: {title.tmdb_id, title.media_type},
      title: title,
      poster_url: Map.get(facts, :poster_url),
      backdrop_url: Map.get(facts, :backdrop_url),
      primary: primary(title, facts),
      scoped?: title.media_type == :tv_series,
      on_watchlist?: Map.fetch!(facts, :on_watchlist?),
      sender: Map.get(facts, :sender),
      note: Map.get(facts, :note),
      recommended_at: Map.get(facts, :recommended_at),
      own?: Map.get(facts, :own?),
      recommendation_id: Map.get(facts, :recommendation_id)
    }
  end

  defp primary(title, facts) do
    cond do
      owner = Map.fetch!(facts, :library_owner_id) -> {:in_library, owner}
      state = Map.fetch!(facts, :acquisition_state) -> {:state, state}
      downloadable?(title, facts) -> :download
      true -> :track
    end
  end

  defp downloadable?(title, facts) do
    Map.fetch!(facts, :release_mode_available) and
      MediaResults.release_status(title, Map.fetch!(facts, :today)) == :released
  end

  @doc "The words a row or the modal shows for an acquisition state."
  @spec acquisition_marker(acquisition_state()) :: String.t() | nil
  def acquisition_marker(:planning), do: "Planning"
  def acquisition_marker(:downloading), do: "Downloading"
  def acquisition_marker(:needs_review), do: "Needs review"
  def acquisition_marker(nil), do: nil

  @doc "`?title=<media_type>-<tmdb_id>` → ref."
  @spec parse_title_ref(String.t()) :: {:ok, {integer(), Title.media_type()}} | :error
  def parse_title_ref("movie-" <> id), do: parse_id(id, :movie)
  def parse_title_ref("tv_series-" <> id), do: parse_id(id, :tv_series)
  def parse_title_ref(_other), do: :error

  defp parse_id(id, media_type) do
    case Integer.parse(id) do
      {tmdb_id, ""} -> {:ok, {tmdb_id, media_type}}
      _other -> :error
    end
  end

  @doc "ref → the `?title=` param value."
  @spec title_ref_param({integer(), Title.media_type()}) :: String.t()
  def title_ref_param({tmdb_id, media_type}), do: "#{media_type}-#{tmdb_id}"
end
```

- [x] **Step 5: Run** — Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add lib/media_centaur_web/components/discovery/title_detail.ex lib/media_centaur_web/live/discovery_live/logic.ex test/media_centaur_web/live/discovery_live/logic_test.exs
git commit -m "feat(discovery): TitleDetail view-model and the page's pure logic"
```

---

### Task 11: `TitleDetailModal` with the split download control

Spec decisions 7, 10, 12, 13, 14 (the tertiary verbs), 16.

**Files:**
- Create: `lib/media_centaur_web/components/discovery/title_detail_modal.ex`
- Create: `storybook/discovery/title_detail_modal.story.exs`
- Modify: `assets/css/app.css`, `lib/media_centaur_web/components/library_cards.ex` (rename `.sort-dropdown*` to the generic `.glass-menu*` idiom both menus share)

Load the `user-interface`, `storybook`, and `writing-copy` skills before this task. Copy is fixed here; the writing-copy pass may adjust words but not the set of controls.

- [x] **Step 1: The menu idiom gets a generic name**

The library sort dropdown's classes carry the sort control's identity. Rename them once so the scope menu and the sort menu share one idiom: in `assets/css/app.css` and `lib/media_centaur_web/components/library_cards.ex`, `.sort-dropdown` → `.glass-menu`, `.sort-dropdown-trigger` → `.glass-menu-trigger`, `.sort-dropdown-chevron` → `.glass-menu-chevron`, `.sort-dropdown-menu` → `.glass-menu-list`, `.sort-dropdown-item` → `.glass-menu-item`, `-active` / `-highlight` suffixes unchanged. Grep tests and E2E specs for `sort-dropdown` and update them. Update the CSS comment above the rules to describe the idiom (a quiet trigger with a chevron and a glass list beneath), not the sort control. The sort control's hand-rolled keyboard handling (`sort_key`, highlight index) stays as it is; its convergence on nav items is scheduled in the spec amendments.

Run: `mise exec -- mix assets.build && mise exec -- mix test test/media_centaur_web/live/library_live_test.exs` — Expected: PASS.

- [x] **Step 2: The component**

```elixir
defmodule MediaCentaurWeb.Components.Discovery.TitleDetailModal do
  @moduledoc """
  The Discovery title detail modal (spec 2026-09-05 §12–16): the depth
  surface for a TMDB title the library does not own, opened by a
  whole-card click on a feed row or a watchlist row. A tenant of the
  cinematic frame like the tracking title modal — backdrop, lockup,
  type and year, overview, and on a feed-born detail the sender and
  their note — rendered from the embedded `TMDB.Title` snapshot with no
  network call on open.

  The action row is the watchlist row's honest three-state rule lifted
  into the modal, with the acquisition state folded in: In library →
  the library detail; Planning / Downloading / Needs review → a stated
  fact (Needs review links to Downloads); Download when the title is
  released and an indexer is ready; Track release otherwise. A series
  Download is a split control — "Download season 1" plus a chevron
  opening "Download all" — reusing the library sort dropdown's
  LiveView-owned menu idiom. Add to watchlist is the secondary,
  replaced by a quiet On watchlist once saved, at which point Remove
  from watchlist appears as a quiet tertiary verb from either tab.
  Delete recommendation is the other tertiary verb, on an own
  recommendation only.

  Pure rendering; every control bubbles to `DiscoveryLive`:
  `close_title`, `title_download` (`scope`), `title_scope_toggle`,
  `title_scope_close`, `title_track`, `title_watchlist_add`,
  `title_watchlist_remove`, `title_recommendation_delete`.

  Nav: the backdrop is the `title_detail` overlay with one body region
  (`config.overlays.title_detail`); every control is a nav item.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.CoreComponents, only: [button: 1, icon: 1]

  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.CinematicShell
  alias MediaCentaurWeb.Components.Detail.TitleLayer
  alias MediaCentaurWeb.Components.Discovery.TitleDetail
  alias MediaCentaurWeb.DiscoveryLive.Logic

  attr :detail, TitleDetail, default: nil, doc: "the open title; nil = closed"
  attr :scope_menu_open, :boolean, default: false, doc: "the series scope menu is showing"

  def title_detail_modal(assigns) do
    ~H"""
    <CinematicShell.cinematic_shell
      id="title-detail-modal"
      open={@detail != nil}
      dismiss={:ephemeral}
      on_close="close_title"
      present={@detail != nil}
      backdrop_url={@detail && @detail.backdrop_url}
      scroll_key={@detail && Logic.title_ref_param(@detail.ref)}
      view_key={:main}
      data-nav-overlay={@detail != nil && "title_detail"}
      data-dismiss-event="close_title"
    >
      <:orientation>
        <div :if={@detail} class="px-6">
          <TitleLayer.lockup title={@detail.title.name} logo_url={nil} />
          <p class="mt-3 flex items-center gap-2 text-xs uppercase tracking-wider text-base-content/55 text-on-image">
            <.icon name={media_icon(@detail.title.media_type)} class="size-4" />
            <span>{media_label(@detail.title.media_type)}</span>
            <span :if={@detail.title.year} class="normal-case tracking-normal">· {@detail.title.year}</span>
          </p>
          <div class="mt-4 flex flex-wrap items-center gap-3 pb-5" data-nav-zone="title_detail_body">
            <.primary detail={@detail} scope_menu_open={@scope_menu_open} />
            <.secondary detail={@detail} />
            <.tertiary detail={@detail} />
          </div>
        </div>
      </:orientation>
      <:body>
        <div :if={@detail} class="space-y-4 px-1 pt-2">
          <p :if={@detail.sender} class="text-xs text-base-content/55">
            <%= if @detail.own? do %>
              You recommended this · {Format.relative_ago(@detail.recommended_at)}
            <% else %>
              Recommended by {@detail.sender} · {Format.relative_ago(@detail.recommended_at)}
            <% end %>
          </p>
          <p :if={@detail.note} class="text-sm">{@detail.note}</p>
          <p :if={@detail.title.overview} class="text-sm text-base-content/70">{@detail.title.overview}</p>
        </div>
      </:body>
    </CinematicShell.cinematic_shell>
    """
  end

  attr :detail, TitleDetail, required: true
  attr :scope_menu_open, :boolean, required: true

  defp primary(%{detail: %{primary: {:in_library, owner_id}}} = assigns) do
    assigns = assign(assigns, :owner_id, owner_id)

    ~H"""
    <.button navigate={"/library?selected=#{@owner_id}"} variant="primary" size="sm" data-nav-item tabindex="0">
      In library <.icon name="hero-chevron-right-mini" class="size-4" />
    </.button>
    """
  end

  defp primary(%{detail: %{primary: {:state, :needs_review}}} = assigns) do
    ~H"""
    <.link navigate="/incoming" class="text-sm text-warning" data-nav-item tabindex="0">
      Needs review <.icon name="hero-chevron-right-mini" class="size-4" />
    </.link>
    """
  end

  defp primary(%{detail: %{primary: {:state, state}}} = assigns) do
    assigns = assign(assigns, :marker, Logic.acquisition_marker(state))

    ~H"""
    <span class="text-sm text-base-content/70">{@marker}</span>
    """
  end

  defp primary(%{detail: %{primary: :download, scoped?: true}} = assigns) do
    ~H"""
    <span class="glass-menu" phx-click-away="title_scope_close" data-captures-keys={@scope_menu_open}>
      <span class="inline-flex">
        <.button
          id="title-download"
          variant="primary"
          size="sm"
          class="rounded-r-none"
          phx-click="title_download"
          phx-value-scope="first_season"
          data-nav-item
          tabindex="0"
        >
          Download season 1
        </.button>
        <.button
          id="title-scope-toggle"
          variant="primary"
          size="sm"
          shape="square"
          class="rounded-l-none border-l border-primary-content/20"
          phx-click="title_scope_toggle"
          aria-label="More download options"
          aria-expanded={@scope_menu_open}
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-chevron-down-mini" class={["size-4", @scope_menu_open && "rotate-180"]} />
        </.button>
      </span>
      <ul :if={@scope_menu_open} id="title-scope-menu" class="glass-menu-list glass-surface">
        <li
          class="glass-menu-item"
          phx-click="title_download"
          phx-value-scope="everything"
          data-nav-item
          tabindex="0"
        >
          Download all
        </li>
      </ul>
    </span>
    """
  end

  defp primary(%{detail: %{primary: :download}} = assigns) do
    ~H"""
    <.button id="title-download" variant="primary" size="sm" phx-click="title_download" data-nav-item tabindex="0">
      Download
    </.button>
    """
  end

  defp primary(%{detail: %{primary: :track}} = assigns) do
    ~H"""
    <.button id="title-track" variant="primary" size="sm" phx-click="title_track" data-nav-item tabindex="0">
      Track release
    </.button>
    """
  end

  attr :detail, TitleDetail, required: true

  defp secondary(%{detail: %{on_watchlist?: true}} = assigns) do
    ~H"""
    <span class="text-sm text-base-content/55">On watchlist</span>
    """
  end

  defp secondary(assigns) do
    ~H"""
    <.button id="title-watchlist-add" variant="secondary" size="sm" phx-click="title_watchlist_add" data-nav-item tabindex="0">
      Add to watchlist
    </.button>
    """
  end

  attr :detail, TitleDetail, required: true

  # Quiet tertiary verbs, each only when it applies: Remove when the
  # title is on the watchlist, Delete for an own recommendation.
  defp tertiary(assigns) do
    ~H"""
    <span class="ml-auto flex items-center gap-3">
      <button
        :if={@detail.on_watchlist?}
        id="title-watchlist-remove"
        type="button"
        class="cursor-pointer text-xs text-base-content/55 transition-colors hover:text-base-content/60"
        phx-click="title_watchlist_remove"
        data-nav-item
        tabindex="0"
      >
        Remove from watchlist
      </button>
      <button
        :if={@detail.own?}
        id="title-recommendation-delete"
        type="button"
        class="cursor-pointer text-xs text-base-content/55 transition-colors hover:text-base-content/60"
        phx-click="title_recommendation_delete"
        data-nav-item
        tabindex="0"
      >
        Delete recommendation
      </button>
    </span>
    """
  end

  defp media_icon(:movie), do: "hero-film"
  defp media_icon(:tv_series), do: "hero-tv"
  defp media_label(:movie), do: "Movie"
  defp media_label(:tv_series), do: "Series"
end
```

Read `MediaCentaurWeb.Components.ReleaseTracking.TitleModal` for `media_icon/1` / `media_label/1` — if they live in a shared helper (`Present`), import from there instead of duplicating.

If `.button` does not accept `shape="square"` combined with `size="sm"` gracefully, drop `shape` and keep the class.

- [x] **Step 3: Story**

`storybook/discovery/title_detail_modal.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Discovery.TitleDetailModal do
  @moduledoc """
  The Discovery title detail modal (spec 2026-09-05) — one surface for
  both tabs. The action row is the honest three-state rule with the
  acquisition state folded in; a series Download is the split control.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.TitleDetail

  def function, do: &MediaCentaurWeb.Components.Discovery.TitleDetailModal.title_detail_modal/1
  def render_source, do: :function
  def layout, do: :one_column

  # A real `position: fixed` overlay — iframe each variation (same
  # treatment as the release-tracking title modal story).
  def container, do: {:iframe, style: "min-height: 640px; width: 100%;"}

  defp movie do
    Title.new!(%{
      tmdb_id: 777,
      media_type: :movie,
      name: "Sample Movie",
      year: "2010",
      release_date: ~D[2010-03-05],
      overview: "A sample movie overview that confirms this is the title you meant."
    })
  end

  defp show do
    Title.new!(%{
      tmdb_id: 42,
      media_type: :tv_series,
      name: "Sample Show",
      year: "2012",
      release_date: ~D[2012-01-01],
      overview: "A sample series overview."
    })
  end

  defp detail(title, overrides) do
    struct!(
      %TitleDetail{
        ref: {title.tmdb_id, title.media_type},
        title: title,
        primary: :download,
        scoped?: title.media_type == :tv_series,
        on_watchlist?: false
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :movie_download,
        description: "A released movie with an indexer: Download, Add to watchlist.",
        attributes: %{detail: detail(movie(), %{})}
      },
      %Variation{
        id: :series_split,
        description: "A series: the split control — Download season 1, chevron for Download all.",
        attributes: %{detail: detail(show(), %{})}
      },
      %Variation{
        id: :series_menu_open,
        description: "The scope menu open, showing the second verb.",
        attributes: %{detail: detail(show(), %{}), scope_menu_open: true}
      },
      %Variation{
        id: :from_friend,
        description: "Feed provenance: who recommended it and their note above the overview; On watchlist as the quiet secondary.",
        attributes: %{
          detail:
            detail(movie(), %{
              sender: "Sample Friend",
              note: "Watch it before anyone spoils the ending.",
              recommended_at: ~U[2026-09-01 10:00:00Z],
              own?: false,
              on_watchlist?: true
            })
        }
      },
      %Variation{
        id: :own_recommendation,
        description: "An own recommendation carries Delete recommendation as the tertiary verb.",
        attributes: %{
          detail: detail(movie(), %{own?: true, recommended_at: ~U[2026-09-01 10:00:00Z]})
        }
      },
      %Variation{
        id: :in_library,
        description: "The library owns it: In library links to the detail, nothing else competes.",
        attributes: %{detail: detail(movie(), %{primary: {:in_library, "0d2c5cd6-0000-4000-8000-000000000001"}})}
      },
      %Variation{
        id: :needs_review,
        description: "A parked plan: Needs review links to Downloads.",
        attributes: %{detail: detail(movie(), %{primary: {:state, :needs_review}})}
      },
      %Variation{
        id: :downloading,
        description: "A pursuit in flight: a stated fact, no verb.",
        attributes: %{detail: detail(movie(), %{primary: {:state, :downloading}})}
      },
      %Variation{
        id: :track,
        description: "Not out yet (or no indexer): Track release.",
        attributes: %{detail: detail(movie(), %{primary: :track})}
      },
      %Variation{
        id: :on_watchlist,
        description: "On the watchlist, from either tab: On watchlist replaces Add, and Remove from watchlist is the tertiary verb.",
        attributes: %{detail: detail(movie(), %{on_watchlist?: true})}
      }
    ]
  end
end
```

- [x] **Step 4: Compile + storybook tests**

Run: `mise exec -- mix compile --warnings-as-errors && mise exec -- mix test test/storybook_compile_test.exs test/storybook_render_test.exs`
Expected: PASS. Fix any Credo MC0008/MC0009 complaint the precommit would raise (typed attrs — `TitleDetail` is a struct attr, which satisfies MC0008).

- [x] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/discovery/title_detail_modal.ex storybook/discovery/title_detail_modal.story.exs assets/css/app.css lib/media_centaur_web/components/library_cards.ex test
git commit -m "feat(discovery): title detail modal with the split download control; glass-menu idiom"
```

---

### Task 12: One `TitleRow` for both tabs

Spec decisions 14, 21 (amended: `FeedRow` and `WatchlistRow` were the same component with different markers; they collapse into one).

**Files:**
- Create: `lib/media_centaur_web/components/discovery/title_row.ex`
- Create: `storybook/discovery/title_row.story.exs`
- Delete: `lib/media_centaur_web/components/discovery/watchlist_row.ex`, `lib/media_centaur_web/live/discovery_live/feed_row.ex`, `storybook/discovery/watchlist_row.story.exs`
- Modify: `lib/media_centaur_web/live/discovery_live/logic.ex` (`row_markers/1`)
- Test: `test/media_centaur_web/live/discovery_live/logic_test.exs`

- [x] **Step 1: Failing test — markers**

Append to `logic_test.exs`:

```elixir
  describe "row_markers/1" do
    test "in library wins, then the acquisition state, then provenance" do
      assert Logic.row_markers(%{library_owner_id: "o", acquisition_state: :downloading, from_nickname: "Sample Friend", on_watchlist?: true}) ==
               ["In library", "from Sample Friend"]

      assert Logic.row_markers(%{library_owner_id: nil, acquisition_state: :needs_review, from_nickname: nil, on_watchlist?: true}) ==
               ["Needs review", "On watchlist"]

      assert Logic.row_markers(%{library_owner_id: nil, acquisition_state: nil, from_nickname: nil, on_watchlist?: false}) == []
    end
  end
```

Run: `mise exec -- mix test test/media_centaur_web/live/discovery_live/logic_test.exs` — Expected: FAIL.

- [x] **Step 2: `Logic.row_markers/1`**

```elixir
  @doc """
  The quiet text markers a Discovery row shows after its type and year,
  in order: the library or acquisition state (one of them — In library
  wins), then provenance (`from <nickname>`), then On watchlist. The feed
  row's sender/when line is the host's, not a marker.
  """
  @spec row_markers(%{
          library_owner_id: Ecto.UUID.t() | nil,
          acquisition_state: acquisition_state(),
          from_nickname: String.t() | nil,
          on_watchlist?: boolean()
        }) :: [String.t()]
  def row_markers(facts) do
    state =
      cond do
        facts.library_owner_id -> "In library"
        marker = acquisition_marker(facts.acquisition_state) -> marker
        true -> nil
      end

    provenance = facts.from_nickname && "from #{facts.from_nickname}"
    watchlist = if facts.on_watchlist? and is_nil(facts.library_owner_id), do: "On watchlist"

    Enum.reject([state, provenance, watchlist], &is_nil/1)
  end
```

The second test case: on the watchlist with `needs_review` shows both, because the state marker and the watchlist marker answer different questions. Adjust the first case's expectation if you decide "On watchlist" should also hide behind In library — the code above hides it (an owned title's watchlist membership is noise); keep the test and code agreeing.

- [x] **Step 3: The component**

`lib/media_centaur_web/components/discovery/title_row.ex`:

```elixir
defmodule MediaCentaurWeb.Components.Discovery.TitleRow do
  @moduledoc """
  One Discovery row — a recommendation on the feed or a watchlist entry —
  as a whole-card click target opening the title detail modal (spec
  2026-09-05 §14). The shared `title_summary/1` identity block, an
  optional lead line (the feed's `from <nickname> · when` / `You · when`),
  the quiet markers the host computed (`DiscoveryLive.Logic.row_markers/1`),
  and the secondary text (a note) in place of the overview. State is
  shown, never acted on here: every verb lives in the modal.

  Pure rendering; `open_title` bubbles to `DiscoveryLive` with the
  title's ref.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.DiscoveryLive.Logic

  attr :id, :string, required: true
  attr :title, Title, required: true
  attr :poster_url, :string, default: nil, doc: "resolved by the host via `LiveHelpers.title_poster_url/1`"
  attr :lead, :string, default: nil, doc: "the feed's sender/when line; nil on the watchlist"
  attr :markers, :list, default: [], doc: "quiet text markers from `Logic.row_markers/1`"
  attr :secondary, :string, default: nil, doc: "a note that displaces the overview"

  def title_row(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class="glass-surface flex w-full cursor-pointer items-start gap-4 rounded-xl px-4 py-3 text-left"
      data-component="title-row"
      phx-click="open_title"
      phx-value-ref={Logic.title_ref_param({@title.tmdb_id, @title.media_type})}
      data-nav-item
      tabindex="0"
    >
      <.title_summary title={@title} poster_url={@poster_url}>
        <:markers>
          <span :if={@lead} class="shrink-0 text-xs text-base-content/55">{@lead}</span>
          <span :for={marker <- @markers} class="shrink-0 text-xs text-base-content/55">{marker}</span>
        </:markers>
        <:secondary :if={@secondary}>{@secondary}</:secondary>
      </.title_summary>
    </button>
    """
  end
end
```

Check `title_summary/1`'s `markers` slot renders multiple children with spacing; if it expects one child, wrap the markers in one `<span class="flex gap-2">`.

- [x] **Step 4: Story**

`storybook/discovery/title_row.story.exs` with variations `bare`, `in_library`, `planning`, `downloading`, `needs_review`, `from_friend_with_note` (lead `"from Sample Friend · 2 days ago"`, marker `"On watchlist"`, secondary note), `own_recommendation` (lead `"You · today"`), `with_poster` (`/images/sample-nosferatu-poster.jpg`). Build the `Title` the way the deleted watchlist_row story did. Delete the old story file.

- [x] **Step 5: Delete the old rows, compile, story tests**

```bash
git rm lib/media_centaur_web/components/discovery/watchlist_row.ex lib/media_centaur_web/live/discovery_live/feed_row.ex storybook/discovery/watchlist_row.story.exs
```

`DiscoveryLive` still references both — Task 13 replaces the render; if `mix compile` fails here, do Task 13's render change before running:

Run: `mise exec -- mix test test/media_centaur_web/live/discovery_live/logic_test.exs test/storybook_compile_test.exs test/storybook_render_test.exs`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add lib/media_centaur_web/components/discovery/title_row.ex storybook/discovery/title_row.story.exs lib/media_centaur_web/live/discovery_live/logic.ex test/media_centaur_web/live/discovery_live/logic_test.exs
git commit -m "feat(discovery): one TitleRow for both tabs — click target, state markers, no verbs"
```

---

### Task 13: `DiscoveryLive` — URL-driven modal, events, acquisition subscription

Spec decisions 14, 15, 17, 18, 19, 20, 21, 22.

**Files:**
- Modify: `lib/media_centaur_web/live/discovery_live.ex`
- Modify: `test/media_centaur_web/live/discovery_live_test.exs`
- Modify: `test/media_centaur_web/page_smoke_test.exs`

- [x] **Step 1: Failing tests**

Replace the tests in `discovery_live_test.exs` that exercise the removed row actions (`"remove deletes the item live"`, `"track action hands off to release tracking"`, the feed `"rows show … add to the watchlist"`, `"Yours shows own rows with Delete…"`, `"the watchlist row no longer offers Recommend"`) with modal-driven equivalents, and add the new ones. Keep every other test. The new block:

```elixir
  describe "title detail modal" do
    setup do
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Settings.Config, :config},
        config
        |> Map.put(:prowlarr_url, "http://prowlarr.test")
        |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
      )

      MediaCentaur.Capabilities.save_test_result(:prowlarr, :ok)
      :ok
    end

    defp released_movie do
      Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie", year: "2005", release_date: ~D[2005-01-01]})
    end

    test "a watchlist card click opens the modal via the URL; close returns", %{conn: conn} do
      {:ok, _} = Discovery.add_to_watchlist(released_movie())
      {:ok, view, _html} = live(conn, "/discovery/watchlist")

      view |> element("#watchlist-item-movie-777") |> render_click()

      assert_patch(view, "/discovery/watchlist?title=movie-777")
      assert has_element?(view, "#title-detail-modal #title-download")
      assert has_element?(view, "#title-detail-modal #title-watchlist-remove")

      view |> element("#title-detail-modal [phx-click='close_title']") |> render_click()
      assert_patch(view, "/discovery/watchlist")
    end

    test "a bad ?title= leaves the modal closed", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=book-1")
      refute has_element?(view, "#title-detail-modal #title-download")
    end

    test "Download creates an automatic plan, closes the modal, flashes, and the row shows the state", %{conn: conn} do
      {:ok, _} = Discovery.add_to_watchlist(released_movie())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      view |> element("#title-download") |> render_click()

      assert_patch(view, "/discovery/watchlist")
      assert render(view) =~ "Finding a release for Sample Movie"
      await_supervised_tasks()
      [plan] = Plans.list_drafts()
      assert plan.approval_policy == "automatic"
      # Nothing found → the plan is ready with a gap → Needs review on the row.
      assert has_element?(view, "#watchlist-item-movie-777", "Needs review")
    end

    test "a series Download offers season 1 and the scope menu's Download all", %{conn: conn} do
      TmdbStubs.stub_series_universe_for_targeting()
      show = Title.new!(%{tmdb_id: 42, media_type: :tv_series, name: "Sample Show", year: "2010", release_date: ~D[2010-01-01]})
      {:ok, _} = Discovery.add_to_watchlist(show)
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=tv_series-42")

      assert has_element?(view, "#title-download", "Download season 1")
      refute has_element?(view, "#title-scope-menu")

      view |> element("#title-scope-toggle") |> render_click()
      assert has_element?(view, "#title-scope-menu", "Download all")

      view |> element("#title-scope-menu li", "Download all") |> render_click()
      await_supervised_tasks()

      [plan] = Plans.list_drafts()
      assert plan.tmdb_type == "tv"
      assert %ReleaseTracking.Item{} = ReleaseTracking.get_item_by_tmdb(42, :tv_series)
    end

    test "Track release from the modal hands off to tracking", %{conn: conn} do
      upcoming = Title.new!(%{tmdb_id: 778, media_type: :movie, name: "Sample Upcoming", release_date: ~D[2999-01-01]})
      {:ok, _} = Discovery.add_to_watchlist(upcoming)
      TmdbStubs.stub_movie_details(%{id: 778, title: "Sample Upcoming"})   # reuse the stub the old track test used
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-778")

      view |> element("#title-track") |> render_click()
      await_supervised_tasks()

      assert %ReleaseTracking.Item{} = ReleaseTracking.get_item_by_tmdb(778, :movie)
    end

    test "Remove from watchlist deletes the item and closes", %{conn: conn} do
      {:ok, _} = Discovery.add_to_watchlist(released_movie())
      {:ok, view, _html} = live(conn, "/discovery/watchlist?title=movie-777")

      view |> element("#title-watchlist-remove") |> render_click()

      assert_patch(view, "/discovery/watchlist")
      refute Discovery.on_watchlist?(777, :movie)
      refute has_element?(view, "#watchlist-item-movie-777")
    end

    test "a feed card opens the modal with provenance; Add to watchlist flips to On watchlist", %{conn: conn} do
      # Reuse this file's existing helpers that create an identity, a friend and a received recommendation.
      rec = receive_recommendation_from_friend("Sample Friend", released_movie(), "Watch it")
      {:ok, view, _html} = live(conn, "/discovery")

      view |> element("#feed-#{rec.id}") |> render_click()
      assert_patch(view, "/discovery?title=movie-777")
      assert render(view) =~ "Recommended by Sample Friend"
      assert render(view) =~ "Watch it"

      view |> element("#title-watchlist-add") |> render_click()
      assert has_element?(view, "#title-detail-modal", "On watchlist")
      assert Discovery.on_watchlist?(777, :movie)
    end

    test "an own recommendation's modal carries Delete recommendation, which withdraws it", %{conn: conn} do
      rec = recommend_as_self(released_movie(), "Mine")
      {:ok, view, _html} = live(conn, "/discovery?title=movie-777")

      view |> element("#title-recommendation-delete") |> render_click()

      assert_patch(view, "/discovery")
      assert Recommendations.get(rec.id).deleted_at
    end

    test "acquisition events refresh the row state without a reload", %{conn: conn} do
      {:ok, _} = Discovery.add_to_watchlist(released_movie())
      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      refute has_element?(view, "#watchlist-item-movie-777", "Needs review")

      {:ok, _plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2005})

      assert has_element?(view, "#watchlist-item-movie-777", "Needs review")
    end
  end
```

Helper notes: `receive_recommendation_from_friend/3` and `recommend_as_self/2` are the names to give private helpers extracted from the file's existing feed tests (they already build a friend + signed event, and call `Recommendations.recommend/2`); read those tests and extract, do not duplicate. `TmdbStubs.stub_series_universe_for_targeting/0` is the fixture Task 6 added. Add `alias MediaCentaur.Acquisition.Plans` to the test module. The "acquisition events refresh" test's "Needs review" assertion targets the row id `#watchlist-item-movie-777`, which the host passes to `TitleRow`; feed rows keep `feed-<recommendation id>`.

Page smoke: add to `test/media_centaur_web/page_smoke_test.exs` beside the discovery entries:

```elixir
          {"/discovery?title=movie-777", "discovery recommendations with the title modal"},
          {"/discovery/watchlist?title=movie-777", "discovery watchlist with the title modal"},
```

with the fixture seeding a watchlist item for 777 (read the file's per-page setup pattern).

- [x] **Step 2: Run** — Expected: FAIL (events undefined, modal absent).

- [x] **Step 3: Implement**

In `lib/media_centaur_web/live/discovery_live.ex`:

Aliases: add `MediaCentaur.Acquisition`, `MediaCentaur.Acquisition.{PlanEvents, Plans, TitleStates}`, `MediaCentaur.Acquisition.Pursuits.Events, as: PursuitEvents`, `MediaCentaurWeb.Components.Discovery.{TitleDetail, TitleDetailModal, TitleRow}`, `MediaCentaurWeb.DiscoveryLive.Logic`, `MediaCentaur.TMDB.Title`; remove the `FeedRow` and `WatchlistRow` aliases. Import `MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1, tmdb_cdn_url: 2]`.

`mount/3`: add `Acquisition.subscribe()` inside `connected?`; assign `title_detail: nil, scope_menu_open: false, today: Date.utc_today()`.

`handle_params/3`: every clause ends by applying the title param —

```elixir
  @impl true
  def handle_params(params, _uri, %{assigns: %{live_action: :friends}} = socket),
    do: {:noreply, socket |> load_friends() |> apply_title_param(params)}

  def handle_params(params, _uri, socket), do: {:noreply, apply_title_param(socket, params)}

  # `?title=<media_type>-<tmdb_id>` drives the modal (UIDR-017 idiom):
  # back closes, refresh keeps it, the URL is shareable. An unknown
  # ref — a title on neither tab — leaves it closed.
  defp apply_title_param(socket, %{"title" => param}) do
    with {:ok, ref} <- Logic.parse_title_ref(param),
         %Title{} = title <- find_title(socket, ref) do
      assign(socket, title_detail: build_title_detail(socket, title), scope_menu_open: false)
    else
      _unknown -> assign(socket, title_detail: nil, scope_menu_open: false)
    end
  end

  defp apply_title_param(socket, _params), do: assign(socket, title_detail: nil, scope_menu_open: false)

  # The title lives on whichever tab knows it: the watchlist item or a feed row.
  defp find_title(socket, ref) do
    case Enum.find(socket.assigns.items, fn %{item: item} -> {item.tmdb_id, item.media_type} == ref end) do
      %{item: item} -> item.title
      nil ->
        case Enum.find(socket.assigns.feed, fn %{recommendation: rec} -> {rec.tmdb_id, rec.media_type} == ref end) do
          %{recommendation: rec} -> rec.title
          nil -> nil
        end
    end
  end
```

Building the detail joins the row facts already loaded:

```elixir
  defp build_title_detail(socket, %Title{} = title) do
    ref = {title.tmdb_id, title.media_type}
    watch_row = Enum.find(socket.assigns.items, &({&1.item.tmdb_id, &1.item.media_type} == ref))
    feed_row = Enum.find(socket.assigns.feed, &({&1.recommendation.tmdb_id, &1.recommendation.media_type} == ref))

    Logic.title_detail(title, %{
      library_owner_id: (watch_row && watch_row.library_owner_id) || (feed_row && feed_row.library_owner_id),
      on_watchlist?: watch_row != nil or (feed_row != nil and feed_row.on_watchlist?),
      acquisition_state: (watch_row && watch_row.acquisition_state) || (feed_row && feed_row.acquisition_state),
      release_mode_available: socket.assigns.prowlarr_ready,
      today: socket.assigns.today,
      poster_url: title_poster_url(title),
      backdrop_url: tmdb_cdn_url(title.backdrop_path, :w1280),
      sender: feed_row && !feed_row.own? && feed_row.nickname,
      note: (feed_row && feed_row.recommendation.note) || (watch_row && watch_row.item.note),
      recommended_at: feed_row && feed_row.recommendation.recommended_at,
      own?: feed_row && feed_row.own?,
      recommendation_id: feed_row && feed_row.recommendation.id
    })
  end
```

Check `tmdb_cdn_url/2`'s accepted widths (`@tmdb_cdn_widths` in `LiveHelpers`); use the largest listed backdrop width.

Acquisition state per row: add `stamp_acquisition_states/1` called at the end of both `load_items/1` and `load_feed/1` (it reads both lists), stamping `acquisition_state` onto each item row and feed row from one `TitleStates.for_refs/1` read over the union of refs. The rows are the one representation — there is no separate states assign. Then refresh the open detail if any:

```elixir
  defp stamp_acquisition_states(socket) do
    refs =
      Enum.map(socket.assigns.items, &{&1.item.tmdb_id, &1.item.media_type}) ++
        Enum.map(socket.assigns.feed, &{&1.recommendation.tmdb_id, &1.recommendation.media_type})

    states = TitleStates.for_refs(Enum.uniq(refs))

    socket
    |> update(:items, fn items ->
      Enum.map(items, &Map.put(&1, :acquisition_state, Map.get(states, {&1.item.tmdb_id, &1.item.media_type})))
    end)
    |> update(:feed, fn feed ->
      Enum.map(feed, &Map.put(&1, :acquisition_state, Map.get(states, {&1.recommendation.tmdb_id, &1.recommendation.media_type})))
    end)
    |> refresh_title_detail()
  end

  defp refresh_title_detail(%{assigns: %{title_detail: nil}} = socket), do: socket

  defp refresh_title_detail(%{assigns: %{title_detail: detail}} = socket),
    do: assign(socket, :title_detail, build_title_detail(socket, detail.title))
```

`mount/3` must assign `feed: []`, `items: []` before the loaders so `stamp_acquisition_states/1` can read both lists on the first pass (order: `assign(...) |> load_items() |> load_feed()` where each loader ends with `stamp_acquisition_states/1`).

Events (replace `watchlist_remove`, `watchlist_track`, `feed_delete`, `feed_add_to_watchlist` with the modal's):

```elixir
  def handle_event("open_title", %{"ref" => ref}, socket),
    do: {:noreply, push_patch(socket, to: discovery_path(socket, %{"title" => ref}))}

  def handle_event("close_title", _params, socket),
    do: {:noreply, push_patch(socket, to: discovery_path(socket))}

  def handle_event("title_scope_toggle", _params, socket),
    do: {:noreply, update(socket, :scope_menu_open, &(!&1))}

  def handle_event("title_scope_close", _params, socket),
    do: {:noreply, assign(socket, :scope_menu_open, false)}

  # Movies send no scope; a series sends first_season or everything.
  def handle_event("title_download", params, %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket) do
    scope =
      case params do
        %{"scope" => scope} when scope in ~w(first_season everything) -> [scope: String.to_existing_atom(scope)]
        _movie -> []
      end

    :ok = Plans.plan_title(detail.title, [approval_policy: "automatic"] ++ scope)

    {:noreply,
     socket
     |> put_flash(:info, "Finding a release for #{detail.title.name}")
     |> push_patch(to: discovery_path(socket))}
  end

  def handle_event("title_track", _params, %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket) do
    ReleaseTracking.track_from_search_async(detail.title)

    {:noreply,
     socket
     |> put_flash(:info, "Tracking #{detail.title.name} — it will appear under Coming up.")
     |> push_patch(to: discovery_path(socket))}
  end

  def handle_event("title_watchlist_add", _params, %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket) do
    attrs =
      if detail.recommendation_id && !detail.own?,
        do: %{source: :friend, recommendation_id: detail.recommendation_id, note: detail.note},
        else: %{}

    case Discovery.add_to_watchlist(detail.title, attrs) do
      {:ok, _item} -> {:noreply, socket}
      {:error, _changeset} -> {:noreply, put_flash(socket, :error, "Could not add that to your watchlist")}
    end
  end

  def handle_event("title_watchlist_remove", _params, %{assigns: %{title_detail: %TitleDetail{ref: {tmdb_id, media_type}}}} = socket) do
    Discovery.remove_from_watchlist(tmdb_id, media_type)
    {:noreply, push_patch(socket, to: discovery_path(socket))}
  end

  def handle_event("title_recommendation_delete", _params, %{assigns: %{title_detail: %TitleDetail{recommendation_id: id}}} = socket)
      when is_binary(id) do
    case Recommendations.delete(id) do
      {:ok, _rec} ->
        {:noreply, socket |> load_feed() |> put_flash(:info, "Recommendation withdrawn") |> push_patch(to: discovery_path(socket))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Only your own recommendations can be deleted")}
    end
  end

  # A modal event with no open modal (stale click after a close) is a no-op.
  def handle_event(event, _params, socket)
      when event in ~w(title_download title_track title_watchlist_add title_watchlist_remove title_recommendation_delete),
      do: {:noreply, socket}
```

Keep `feed_scope`, `add_friend`, `remove_friend`. Alias `MediaCentaurWeb.Components.Discovery.TitleDetail`.

The path helper keeps the tab:

```elixir
  defp discovery_path(socket, params \\ %{}) do
    base = current_path(socket.assigns.live_action)

    case URI.encode_query(params) do
      "" -> base
      query -> base <> "?" <> query
    end
  end
```

`handle_info`: the watchlist clauses re-run both loaders as today (the loaders now stamp states). Add acquisition:

```elixir
  def handle_info(%PlanEvents.Changed{}, socket), do: {:noreply, stamp_acquisition_states(socket)}

  def handle_info(%struct{}, socket) when PursuitEvents.is_event(struct), do: {:noreply, stamp_acquisition_states(socket)}
```

Check `PursuitEvents.is_event/1` is a public guard (IncomingLive uses it); place these clauses above the catch-all `handle_info(_message, socket)`. `PlanEvents.SearchActivity`/`DescentStatus` structs also arrive on the topic and fall to the catch-all.

Render: add the modal to the overlays slot and pass the new row attrs:

```heex
      <:overlays>
        <TitleDetailModal.title_detail_modal detail={@title_detail} scope_menu_open={@scope_menu_open} />
      </:overlays>
```

Both tabs render `TitleRow`. Feed:

```heex
            <TitleRow.title_row
              :for={row <- scoped_feed(@feed, @feed_scope)}
              id={"feed-#{row.recommendation.id}"}
              title={row.recommendation.title}
              poster_url={row.poster_url}
              lead={feed_lead(row)}
              markers={Logic.row_markers(%{library_owner_id: row.library_owner_id, acquisition_state: row.acquisition_state, from_nickname: nil, on_watchlist?: row.on_watchlist?})}
              secondary={row.recommendation.note}
            />
```

with

```elixir
  defp feed_lead(%{own?: true, recommendation: rec}), do: "You · #{Format.relative_ago(rec.recommended_at)}"
  defp feed_lead(%{nickname: nickname, recommendation: rec}), do: "from #{nickname} · #{Format.relative_ago(rec.recommended_at)}"
```

Watchlist:

```heex
            <TitleRow.title_row
              :for={row <- @items}
              id={"watchlist-item-#{row.item.media_type}-#{row.item.tmdb_id}"}
              title={row.item.title}
              poster_url={row.poster_url}
              markers={Logic.row_markers(%{library_owner_id: row.library_owner_id, acquisition_state: row.acquisition_state, from_nickname: row.from_nickname, on_watchlist?: false})}
              secondary={row.item.note}
            />
```

(A watchlist row never says "On watchlist" about itself — `on_watchlist?: false` there is the tab's own fact.)

`@prowlarr_ready` stays an assign (the detail builder reads it); find where it is set today (`grep -n prowlarr_ready lib/media_centaur_web/live/discovery_live.ex`) and keep that.

Moduledoc: rewrite the first two paragraphs to describe the two tabs as lists of whole-card click targets that open the title detail modal (`?title=`), where every verb lives; note the acquisition subscription and `TitleStates`.

- [x] **Step 4: Run**

Run: `mise exec -- mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/live/discovery_live/logic_test.exs test/media_centaur_web/page_smoke_test.exs`
Expected: PASS. The "acquisition events refresh" test relies on `Plans.create_movie_plan` broadcasting `PlanEvents.Changed` on `acquisition:updates` — confirm `Acquisition.subscribe/0` subscribes to that topic (read `lib/media_centaur/acquisition.ex:202`).

- [x] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/discovery_live.ex test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/page_smoke_test.exs test/support/tmdb_stubs.ex test/media_centaur/acquisition/plans_test.exs
git commit -m "feat(discovery): URL-driven title detail modal, one-click download, live acquisition state"
```

---

### Task 14: Nav overlay for the modal

Spec decisions 10, 16. Load the `input-system` skill first.

**Files:**
- Modify: `assets/js/input/config.js`
- Modify: `assets/js/input/__tests__/discovery_behavior.test.js` (or the config test file the skill names)

- [x] **Step 1: Failing bun test**

Add to the discovery behaviour test file:

```js
import { NAV_CONFIG } from "../config.js"   // use the actual export name — read config.js's export

test("the title_detail overlay has one body region", () => {
  expect(NAV_CONFIG.overlays.title_detail).toEqual({
    entry: ["title_detail_body"],
    layout: { title_detail_body: {} },
  })
})
```

Run: `bun test assets/js/input/` — Expected: FAIL.

- [x] **Step 2: Config**

In `config.js` `overlays`, after `plan`:

```js
    // The Discovery title detail modal (spec 2026-09-05). One region: the
    // action row — primary, secondary, tertiary verbs, and the series scope
    // menu's item when open — walked as one list. BACK dismisses.
    title_detail: {
      entry: ["title_detail_body"],
      layout: { title_detail_body: {} },
    },
```

If overlays also need a `contextItems`/`alwaysPopulated` entry (compare how `plan_body` is listed elsewhere in the file), mirror it for `title_detail_body`.

- [x] **Step 3: Run** — `bun test assets/js/input/` — Expected: PASS. Then `mise exec -- mix assets.build`.

- [x] **Step 4: Trace**

With the dev service restarted and a watchlist item present on the dev DB, run `mc-nav-trace` (see `~/scripts/agents/`, run with no args for usage) against `http://127.0.0.1:2160/discovery/watchlist`: DOWN to a row, SELECT opens the modal, LEFT/RIGHT walks the action row, the chevron SELECT opens the menu and DOWN reaches "Download all", BACK closes. Fix any clipped-focus report before committing. Clean up any plan or tracking item created on the dev DB while probing (`Plans.discard/1` via Tidewave, remove the tracking item on Incoming).

- [x] **Step 5: Commit**

```bash
git add assets/js/input/config.js assets/js/input/__tests__/discovery_behavior.test.js
git commit -m "feat(input): title_detail nav overlay for the Discovery modal"
```

---

### Task 15: Records and docs

Spec "Documentation", decision 27; spec amendments from Tasks 7 and 9.

**Files:**
- Create: `decisions/user-interface/2026-09-05-030-follow-up-pill-and-condition-dot.md`
- Modify: `decisions/README.md`, `docs/GLOSSARY.md`, `decisions/architecture/2026-06-10-056-release-tracking-wants.md`, `docs/superpowers/specs/2026-09-05-one-click-download-design.md`
- Modify (wiki repo): `../media-centaur.wiki/Discovery.md` (or the page named for Discovery — `ls ../media-centaur.wiki | grep -i discov`), `Searching-and-Downloading.md`, `Keyboard-and-Gamepad.md`

- [x] **Step 1: UIDR-030**

```markdown
---
status: accepted
date: 2026-09-05
---
# Follow-up pill and condition dot — the sidebar's two badge idioms

## Context and Problem Statement

The sidebar rendered one idea three ways: the Status count cleared when
the page was visited, the Review count persisted until the files were
handled, and Incoming had nothing even when a draft plan sat waiting for
approval. Each new page with pending decisions was about to invent its
own chrome.

## Decision Outcome

Chosen option: two named idioms and no others.

* **Follow-up pill** — a count of items on that page waiting on a
  decision from the user. Persists until the items are handled, and each
  source defines handling: approve or discard a plan, review a file,
  look at an incident. One component
  (`MediaCentaurWeb.Components.FollowUpPill`), one variant (error), one
  size, one placement rule: the row's end in the expanded rail, the
  icon's top-right corner in the 52px rail. Sources today: Incoming
  (plans in `ready`), Review (pending files + mappings), Status (unseen
  incidents).
* **Condition dot** — something is wrong right now; persists until
  resolved. Status only (error buckets), at the icon's bottom-right so
  it never overlaps the pill.

The pill is domain state, not attention tracking: it counts what is
waiting regardless of which page or modal is open. A new page with
pending decisions adds a source to `MediaCentaurWeb.ShellBadges.Counts`
and one `relevant?/1` clause — never new chrome.

### Consequences

* Good, because every "waiting on you" reads the same and a future page
  has one thing to add.
* Good, because the pill survives the collapsed rail, which used to clip
  the Review count.
* Bad, because the Review count changed from blue to red; if it proves
  too loud in daily use the remedy is one non-error variant for all
  three, never a second colour.
```

Add the row to `decisions/README.md` (regenerate the index the way the README says; if it is hand-maintained, append `| 030 | 2026-09-05 | [Follow-up pill and condition dot — the sidebar's two badge idioms](user-interface/2026-09-05-030-follow-up-pill-and-condition-dot.md) | accepted |`).

- [x] **Step 2: Glossary**

`docs/GLOSSARY.md` — under **Acquisition** add rows for **Approval policy**, **Clean plan**, **Download scope**; under **UI and input system** add **Follow-up pill**, **Condition dot**, **Title detail modal**, **Acquisition state**. Wording from the spec's glossary, each row naming its owner module (`Plans.Plan`, `Plans.clean?/1`, `Plans.DownloadScope`, `Components.FollowUpPill`, `Layouts`, `Components.Discovery.TitleDetailModal`, `Acquisition.TitleStates`).

- [x] **Step 3: ADR-056 note**

Append under its Consequences or a new "Amendments" heading:

```markdown
**2026-09-05 amendment.** The mode gate's decision is now stamped on the
plan as `approval_policy` (`automatic` | `review`) at creation and read
by `Reactor.Handlers.plan_changed/1` for every plan, not only tracking
ones. The mode-off veto remains a live read. See
`docs/superpowers/specs/2026-09-05-one-click-download-design.md`.
```

- [x] **Step 4: Spec amendments**

Append to the spec:

```markdown
## Amendments (implementation)

- §20: `Acquisition.TitleStates.for_refs/1` takes the page's list of refs and returns a map, one query per table, instead of a per-title function.
- §24: one CSS rule keyed off `--sidebar-expanded` places the pill (row's end expanded, icon's top-right collapsed); the Status condition dot moved to the icon's bottom-right.
- §14: the tertiary verbs are "Remove from watchlist" (whenever the title is on the watchlist, from either tab) and "Delete recommendation" (own recommendation). The feed row and the watchlist row collapsed into one `TitleRow` component.
- §17: the context function is `Plans.plan_title/2` with `approval_policy:` and `scope:` explicit; one asynchronous contract for movies and series.
- §23: "persists until handled" means each source defines handling — the Status source's seen-marker is its definition.
- §10: the sort dropdown's CSS became the generic `.glass-menu*` idiom both menus share. **Scheduled convergence:** the sort control's hand-rolled keyboard model (`sort_key`, highlight index) adopts nav items the next time the library toolbar is touched.
```

- [x] **Step 5: Wiki**

In `~/src/media-centaur/media-centaur.wiki`: the Discovery page gets a "Opening a title" section (card click, the modal, In library / Download / Track release, Add to watchlist, the series split "Download season 1" / "Download all" and that Download all also follows new episodes), and a "What happens after Download" paragraph (a release is searched for; a clean result starts the download by itself; anything that needs a decision parks on Downloads and the Incoming entry in the sidebar shows a count). `Searching-and-Downloading.md` gets the same parked-for-review sentence under its drafts section. `Keyboard-and-Gamepad.md` gets one line for the split control (chevron opens the menu, down/select picks). Commit with `git commit -m "wiki: discovery title modal, one-click download, follow-up pill"`. Do not push.

- [x] **Step 6: Commit (app repo)**

```bash
git add decisions docs
git commit -m "docs: UIDR-030 follow-up pill, glossary, ADR-056 amendment, spec amendments"
```

---

### Task 16: Precommit, flake check, real-browser verification

- [x] **Step 1:** `mise exec -- mix precommit` — fix everything it reports (warnings are bugs; Credo MC0008/MC0009/MC0023/MC0024 in particular).

- [x] **Step 2:** `mise exec -- mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur/acquisition/reactor/handlers_test.exs --repeat-until-failure 10` — Expected: no failure.

- [x] **Step 3:** Restart `media-centaur-dev`. In the real browser (the owner's, or `mc-debug-browser`): open `/discovery/watchlist`, click a released movie card, click Download, watch the modal close and the flash appear, confirm the row shows Planning then either Downloading (when an indexer finds it) or Needs review with the Incoming pill lit. Approve or discard the plan on Incoming and confirm the pill clears. Clean up any test rows afterwards.

- [x] **Step 4:** Final commit if the precommit changed anything: `git commit -am "chore: precommit fixes for one-click download"`.

---

## Release notes draft (for the next `/ship`)

- Recommendations and watchlist entries open a detail view. Download from there starts the search and, when a good release is found, the download itself.
- Series downloads default to season 1; the chevron offers Download all, which also follows new episodes.
- A download that needs your decision parks on Downloads, and the Incoming entry in the sidebar now shows how many are waiting. Review and Status use the same pill.
- Migration: adds `approval_policy` to plans, default review. Safe on every existing row.

## Self-review

- Spec coverage: §1–6 → Tasks 1–3; §7–11 → Tasks 5, 6, 11; §12–16 → Tasks 10–14; §17–19 → Task 6, 13; §20–22 → Tasks 7, 12, 13; §23–27 → Tasks 8, 9, 15; data changes → Task 1; testing → every task; documentation → Task 15.
- Names used consistently: `approval_policy` (`"automatic"`/`"review"`), `Plans.clean?/1`, `Plans.count_awaiting_review/0`, `Plans.plan_title/2` (`approval_policy:`, `scope: :first_season | :everything`), `Plans.DownloadScope.units/2`, `TitleStates.for_refs/1`, `ShellBadges.Counts` / `badges` attr, `FollowUpPill.follow_up_pill/1`, `TitleDetail`, `Logic.title_detail/2`, `Logic.acquisition_marker/1`, `Logic.parse_title_ref/1`, `Logic.title_ref_param/1`, `Logic.row_markers/1`, `TitleRow.title_row/1`, `TitleDetailModal.title_detail_modal/1`, events `open_title`/`close_title`/`title_download`/`title_scope_toggle`/`title_scope_close`/`title_track`/`title_watchlist_add`/`title_watchlist_remove`/`title_recommendation_delete`, overlay `title_detail` / region `title_detail_body`.
