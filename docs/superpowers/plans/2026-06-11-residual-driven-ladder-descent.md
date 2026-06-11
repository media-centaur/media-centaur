# Residual-Driven Ladder Descent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the plan runner search the coverage ladder lazily — descend a rung only for units the solver's residual leaves uncovered — narrate the descent to the user, and give the swap picker an on-demand "find more" search.

**Architecture:** `RunPlan` becomes a rung loop (search rung → solve → stop when residual empty); `LadderTerms` gains rung-scoped constructors; a new transient `PlanEvents.DescentStatus` broadcast feeds a pure `DescentNarrative` view-model rendered in the plan modal; `Plans.search_alternatives/1` live-fills the corpus for one unit's terms when the user clicks "Find more". The planner (`Planner.solve/3`) is untouched.

**Tech Stack:** Elixir/Phoenix LiveView, Oban (inline in tests), `Req.Test` Prowlarr stubs, Phoenix Storybook.

**Spec:** `docs/superpowers/specs/2026-06-11-residual-driven-ladder-descent-design.md`

**Project rules that bind every task:** test-first (red → green), zero warnings, generic titles only (`Sample Show`), commit per task on `main`, never push.

---

## File Map

| File | Role |
|---|---|
| `lib/media_centaur/acquisition/plans/ladder_terms.ex` | Modify — rung constructors (`series_terms/1`, `season_terms/2`, `episode_terms/2`); `for_plan/2` becomes their concatenation |
| `test/media_centaur/acquisition/plans/ladder_terms_test.exs` | Create — constructor + invariant tests |
| `lib/media_centaur/acquisition/jobs/run_plan.ex` | Modify — descent loop replaces `gather_options/4`; descent broadcasts |
| `test/media_centaur/acquisition/jobs/run_plan_test.exs` | Create — descent scenarios + broadcast sequence |
| `test/media_centaur/acquisition/plans_test.exs` | Modify — lifecycle test's exclusion stub; swap-picker test exercises `search_alternatives` |
| `lib/media_centaur/acquisition/plan_events.ex` | Modify — add `DescentStatus` |
| `lib/media_centaur/acquisition/plans.ex` | Modify — add `search_alternatives/1` |
| `lib/media_centaur/acquisition/view_models/descent_narrative.ex` | Create — pure narrative view-model |
| `test/media_centaur/acquisition/view_models/descent_narrative_test.exs` | Create — narrative unit tests |
| `lib/media_centaur_web/live/acquisition_live.ex` | Modify — find-more event/async; descent assign + handle_info |
| `lib/media_centaur_web/components/acquisition/plan_modal.ex` | Modify — find-more button; descent panel |
| `storybook/acquisition/plan_modal.story.exs` | Modify — new variations (MC0009) |
| `test/media_centaur_web/live/acquisition_live_test.exs` | Modify — swap-picker UI test exercises find-more; descent panel test |

Tasks 1→2 are the engine; 3 adds the event stream; 4 the picker seam; 5→7 the UI; 8 ships.

---

### Task 1: `LadderTerms` rung constructors

**Files:**
- Modify: `lib/media_centaur/acquisition/plans/ladder_terms.ex`
- Create: `test/media_centaur/acquisition/plans/ladder_terms_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Acquisition.Plans.LadderTermsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Plans.{LadderTerms, Plan}

  defp plan, do: %Plan{title: "Sample Show", tmdb_type: "tv"}

  describe "rung constructors" do
    test "series_terms/1 is the one broad term" do
      assert LadderTerms.series_terms(plan()) == [{"Sample Show", [type: :tv]}]
    end

    test "season_terms/2 emits both text forms per season, in order" do
      assert LadderTerms.season_terms(plan(), [1, 3]) == [
               {"Sample Show Season 1", [type: :tv]},
               {"Sample Show S01", [type: :tv]},
               {"Sample Show Season 3", [type: :tv]},
               {"Sample Show S03", [type: :tv]}
             ]
    end

    test "episode_terms/2 emits one zero-padded term per unit" do
      assert LadderTerms.episode_terms(plan(), [{1, 2}, {10, 11}]) == [
               {"Sample Show S01E02", [type: :tv]},
               {"Sample Show S10E11", [type: :tv]}
             ]
    end
  end

  describe "the for_plan invariant" do
    # for_unit/2 (the swap picker's term universe) and the corpus keys
    # both build on for_plan/2 — the rung constructors must concatenate
    # to exactly it, or lazy descent and the picker drift apart.
    test "for_plan/2 is series ++ seasons ++ episodes" do
      wanted = [{2, 1}, {1, 3}, {1, 1}]
      seasons = wanted |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()

      assert LadderTerms.for_plan(plan(), wanted) ==
               LadderTerms.series_terms(plan()) ++
                 LadderTerms.season_terms(plan(), seasons) ++
                 LadderTerms.episode_terms(plan(), wanted)
    end

    test "movie plans are unaffected" do
      movie_plan = %Plan{title: "Sample Movie", tmdb_type: "movie", year: 2010}
      assert LadderTerms.for_plan(movie_plan, []) == [{"Sample Movie 2010", [type: :movie]}]
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/media_centaur/acquisition/plans/ladder_terms_test.exs`
Expected: FAIL — `function MediaCentaur.Acquisition.Plans.LadderTerms.series_terms/1 is undefined`

- [ ] **Step 3: Implement the constructors**

In `lib/media_centaur/acquisition/plans/ladder_terms.ex`, replace the `def for_plan(%Plan{tmdb_type: "tv"} ...)` clause and add the constructors (keep `for_plan` movie clause, `for_unit/2`, `movie_term/1`, `pad/1` as they are):

```elixir
  def for_plan(%Plan{tmdb_type: "tv"} = plan, wanted) do
    seasons = wanted |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
    series_terms(plan) ++ season_terms(plan, seasons) ++ episode_terms(plan, wanted)
  end

  @doc "The broadest rung — one term for an all-in-one release."
  @spec series_terms(Plan.t()) :: [term_pair()]
  def series_terms(%Plan{} = plan), do: [{plan.title, [type: :tv]}]

  @doc "The season rung — both text forms per season, broad-to-narrow within the rung."
  @spec season_terms(Plan.t(), [pos_integer()]) :: [term_pair()]
  def season_terms(%Plan{} = plan, seasons) do
    Enum.flat_map(seasons, fn season ->
      [
        {"#{plan.title} Season #{season}", [type: :tv]},
        {"#{plan.title} S#{pad(season)}", [type: :tv]}
      ]
    end)
  end

  @doc "The episode rung — one term per `{season, episode}` unit."
  @spec episode_terms(Plan.t(), [{pos_integer(), pos_integer()}]) :: [term_pair()]
  def episode_terms(%Plan{} = plan, units) do
    Enum.map(units, fn {season, episode} ->
      {"#{plan.title} S#{pad(season)}E#{pad(episode)}", [type: :tv]}
    end)
  end
```

Also update the moduledoc's first paragraph to mention the rung constructors:

```elixir
  @moduledoc """
  The coverage ladder's search terms — single source of truth shared by
  the plan runner (rung by rung, via `series_terms/1` / `season_terms/2`
  / `episode_terms/2`), the alternatives picker (one unit), and the
  corpus keys, so none of them can drift on what "this plan's searches"
  means. `for_plan/2` is exactly the rung constructors concatenated —
  an invariant pinned by the test suite.

  TV terms run broad-to-narrow: the series title, `Title Season N` +
  `Title SNN` per season, `Title SNNENN` per episode. Movies are one
  term (`Title [year]`). All terms pair with the Prowlarr `type` opt —
  the corpus keys on term + type.
  """
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/media_centaur/acquisition/plans/ladder_terms_test.exs`
Expected: PASS (5 tests)

- [ ] **Step 5: Run the acquisition suite to confirm nothing else moved**

Run: `mix test test/media_centaur/acquisition/`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/acquisition/plans/ladder_terms.ex test/media_centaur/acquisition/plans/ladder_terms_test.exs
git commit -m "refactor(acquisition): rung-scoped ladder term constructors"
```

---

### Task 2: `RunPlan` residual-driven descent

**Files:**
- Modify: `lib/media_centaur/acquisition/jobs/run_plan.ex` (replace `run_tv/3` + `gather_options/4`)
- Create: `test/media_centaur/acquisition/jobs/run_plan_test.exs`
- Modify: `test/media_centaur/acquisition/plans_test.exs` (exclusion-replan stub)

- [ ] **Step 1: Write the failing descent tests**

Create `test/media_centaur/acquisition/jobs/run_plan_test.exs`. The Prowlarr setup mirrors `plans_test.exs` (the established pattern for plan tests); the stub additionally `send`s every searched query to the test process so descent behavior is asserted on *which terms were searched*, not just outcomes. `Plans.create_series_plan/2` runs the Oban job inline, so messages are in the mailbox before the assertions run.

```elixir
defmodule MediaCentaur.Acquisition.Jobs.RunPlanTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.Search.Prowlarr

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)

    config = :persistent_term.get({MediaCentaur.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
    )

    on_exit(fn ->
      :persistent_term.erase({Prowlarr, :client})
      :persistent_term.put({MediaCentaur.Config, :config}, config)
    end)

    :ok
  end

  defp selection do
    %Targeting.Selection{
      tmdb_id: "246810",
      title: "Sample Show",
      tracked?: false,
      seasons: [
        %Targeting.Season{
          season_number: 1,
          episodes:
            for episode <- 1..3 do
              %Targeting.Episode{
                season_number: 1,
                episode_number: episode,
                label: "Episode #{episode}",
                aired?: true,
                in_library?: false
              }
            end
        },
        %Targeting.Season{
          season_number: 2,
          episodes: [
            %Targeting.Episode{
              season_number: 2,
              episode_number: 1,
              label: "Return",
              aired?: true,
              in_library?: false
            }
          ]
        }
      ]
    }
  end

  defp release(title, guid, attrs) do
    Map.merge(
      %{
        "title" => title,
        "guid" => guid,
        "indexerId" => 1,
        "indexer" => "indexer-a",
        "seeders" => Map.get(attrs, :seeders, 10)
      },
      Map.new(Map.delete(attrs, :seeders), fn {key, value} -> {to_string(key), value} end)
    )
  end

  # Serves results_by_query and reports every live GET search back to
  # the test process — the descent assertions read the mailbox.
  defp stub_recording_searches(results_by_query) do
    test_pid = self()

    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/search"} ->
          %{"query" => query} = URI.decode_query(conn.query_string)
          send(test_pid, {:searched, query})
          Req.Test.json(conn, Map.get(results_by_query, query, []))

        {"POST", "/api/v1/search"} ->
          Req.Test.json(conn, %{"approved" => true})

        _other ->
          Req.Test.json(conn, %{})
      end
    end)
  end

  describe "residual-driven descent" do
    test "an acceptable complete-series pack stops the descent at the series rung" do
      stub_recording_searches(%{
        "Sample Show" => [
          release("Sample.Show.S01-02.COMPLETE.1080p.WEB-DL", "series-pack", %{seeders: 20})
        ]
      })

      {:ok, plan} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}, {1, 3}, {2, 1}])

      units = Plans.units_for(plan.id)
      assert Enum.all?(units, &(&1.status == "found"))
      assert Enum.all?(units, &(&1.assigned_guid == "series-pack"))

      assert_received {:searched, "Sample Show"}
      refute_received {:searched, "Sample Show Season 1"}
      refute_received {:searched, "Sample Show S01"}
      refute_received {:searched, "Sample Show S01E01"}
      refute_received {:searched, "Sample Show S02E01"}
    end

    test "season packs satisfy the residual — the episode rung is never searched" do
      stub_recording_searches(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{seeders: 30})
        ],
        "Sample Show Season 2" => [
          release("Sample.Show.S02.COMPLETE.1080p.WEB-DL", "pack-s2", %{seeders: 30})
        ]
      })

      {:ok, plan} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}, {1, 3}, {2, 1}])

      units = Plans.units_for(plan.id)
      season_one_units = Enum.filter(units, &(&1.season_number == 1))
      assert Enum.all?(season_one_units, &(&1.assigned_guid == "pack-s1"))
      assert Enum.find(units, &(&1.season_number == 2)).assigned_guid == "pack-s2"

      assert_received {:searched, "Sample Show"}
      assert_received {:searched, "Sample Show Season 1"}
      assert_received {:searched, "Sample Show S01"}
      assert_received {:searched, "Sample Show Season 2"}
      assert_received {:searched, "Sample Show S02"}
      refute_received {:searched, "Sample Show S01E01"}
      refute_received {:searched, "Sample Show S01E02"}
      refute_received {:searched, "Sample Show S01E03"}
      refute_received {:searched, "Sample Show S02E01"}
    end

    test "episode terms are searched only for units the broader rungs left uncovered" do
      stub_recording_searches(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{seeders: 30})
        ],
        "Sample Show S02E01" => [
          release("Sample.Show.S02E01.1080p.WEB-DL", "single-s2e1", %{seeders: 12})
        ]
      })

      {:ok, plan} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}, {1, 3}, {2, 1}])

      units = Plans.units_for(plan.id)
      assert Enum.find(units, &(&1.season_number == 2)).assigned_guid == "single-s2e1"

      assert_received {:searched, "Sample Show S02E01"}
      refute_received {:searched, "Sample Show S01E01"}
      refute_received {:searched, "Sample Show S01E02"}
      refute_received {:searched, "Sample Show S01E03"}
    end

    test "a dry show walks the full ladder and reports every unit unfound" do
      stub_recording_searches(%{})

      {:ok, plan} = Plans.create_series_plan(selection(), [{2, 1}])

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "unfound"

      assert_received {:searched, "Sample Show"}
      assert_received {:searched, "Sample Show Season 2"}
      assert_received {:searched, "Sample Show S02"}
      assert_received {:searched, "Sample Show S02E01"}
    end

    test "an elevated per-unit floor keeps that unit in the residual past an acceptable pack" do
      stub_recording_searches(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{seeders: 30})
        ],
        "Sample Show S01E01" => [
          release("Sample.Show.S01E01.2160p.WEB-DL.x265", "e1-uhd", %{seeders: 8})
        ]
      })

      {:ok, plan} =
        Plans.create_tracking_plan(
          %{tmdb_id: "246810", tmdb_type: "tv", title: "Sample Show"},
          [
            %{season_number: 1, episode_number: 1, label: "S01E01", position: 0, min_quality: "uhd_4k"},
            %{season_number: 1, episode_number: 2, label: "S01E02", position: 1},
            %{season_number: 1, episode_number: 3, label: "S01E03", position: 2}
          ]
        )

      units = Plans.units_for(plan.id)
      assert Enum.find(units, &(&1.episode_number == 1)).assigned_guid == "e1-uhd"
      assert Enum.find(units, &(&1.episode_number == 2)).assigned_guid == "pack-s1"
      assert Enum.find(units, &(&1.episode_number == 3)).assigned_guid == "pack-s1"

      # Descent was per-unit: only the elevated unit's episode term ran.
      assert_received {:searched, "Sample Show S01E01"}
      refute_received {:searched, "Sample Show S01E02"}
      refute_received {:searched, "Sample Show S01E03"}
    end
  end
end
```

Notes for the implementer:
- `"Sample.Show.S01-02.COMPLETE.1080p"` is the exact season-range form `ReleaseCoverage.classify/1` pins in `test/media_centaur/search/release_coverage_test.exs:51` — don't invent a new spelling.
- `min_quality: "uhd_4k"` uses the `Quality` label vocabulary (`"hd_1080p"` / `"uhd_4k"`, see `AutoGrabSettings` defaults). `Plans.create_tracking_plan/2` is the public API that accepts per-unit floors (the ADR-056 patience elevation).

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `mix test test/media_centaur/acquisition/jobs/run_plan_test.exs`
Expected: FAIL — the first three tests fail on `refute_received` (the current runner searches every term); the dry-show test may already pass.

- [ ] **Step 3: Implement the descent loop**

In `lib/media_centaur/acquisition/jobs/run_plan.ex`:

**3a.** Replace `run_tv/3` and delete `gather_options/4` entirely (keep `series_criteria/1`, `assignment_attrs/2`, `scope_label/1`, `run_movie/3`, `search/4`, `prefs/1`, `pad/1`):

```elixir
  defp run_tv(plan, units, force?) do
    wanted = Enum.map(units, &{&1.season_number, &1.episode_number})
    excluded = units |> Enum.flat_map(& &1.excluded_release_guids) |> MapSet.new()
    identity = series_criteria(plan)
    plan_prefs = prefs(plan)

    # One solve per quality-floor group (ADR-056 Q4): a unit inside its
    # patience window carries an elevated `min_quality`, fails its
    # group's acceptability, and stays in the residual — so the descent
    # continues for it alone. The planner stays time-blind.
    floor_groups =
      units
      |> Enum.group_by(&(&1.min_quality || plan_prefs.min_quality))
      |> Map.new(fn {floor, group_units} ->
        {floor, Enum.map(group_units, &{&1.season_number, &1.episode_number})}
      end)

    initial = %{options: [], terms_by_guid: %{}, assignment_by_unit: %{}, residual: wanted}

    state =
      Enum.reduce_while(rungs(plan), initial, fn {_rung_id, terms_for}, state ->
        state =
          state
          |> gather_rung(plan, terms_for.(state.residual), identity, excluded, force?)
          |> solve_groups(wanted, floor_groups, plan_prefs)

        if state.residual == [], do: {:halt, state}, else: {:cont, state}
      end)

    Enum.each(units, fn unit ->
      key = {unit.season_number, unit.episode_number}

      case Map.get(state.assignment_by_unit, key) do
        nil ->
          {:ok, _} = Repo.update(PlanUnit.unfound_changeset(unit))

        assignment ->
          {:ok, _} =
            Repo.update(
              PlanUnit.assign_changeset(unit, assignment_attrs(assignment, state.terms_by_guid))
            )
      end
    end)
  end

  # The coverage ladder, broad to narrow. Each rung sees the current
  # residual — the wanted units no acceptable option covers yet — and
  # emits only the terms that residual justifies. The descent never
  # searches below a span the solver already covered.
  defp rungs(plan) do
    [
      {:series, fn _residual -> LadderTerms.series_terms(plan) end},
      {:seasons,
       fn residual ->
         seasons = residual |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
         LadderTerms.season_terms(plan, seasons)
       end},
      {:episodes, fn residual -> LadderTerms.episode_terms(plan, residual) end}
    ]
  end

  # One rung's searches folded into the cumulative option pool. Every
  # term goes through the corpus; identity is verified per result;
  # plan-wide exclusions are dropped before solving (a release the user
  # rejected for one episode is almost never what they want for
  # another); guid dedup keeps the first term that surfaced a release.
  defp gather_rung(state, plan, terms, identity, excluded, force?) do
    Enum.reduce(terms, state, fn {term, opts}, state ->
      plan
      |> search(term, opts, force?)
      |> Enum.reduce(state, fn result, state ->
        with false <- ReleaseRedFlags.suspicious?(result.title, result.size_bytes),
             false <- MapSet.member?(excluded, result.guid),
             false <- Map.has_key?(state.terms_by_guid, result.guid),
             {:ok, scope} <- TitleMatcher.coverage(result, identity) do
          %{
            state
            | options: [%Planner.Option{result: result, scope: scope} | state.options],
              terms_by_guid: Map.put(state.terms_by_guid, result.guid, term)
          }
        else
          _ -> state
        end
      end)
    end)
  end

  # Re-solves every floor group over the cumulative pool and recomputes
  # the residual. Rebuilt from scratch each rung — the planner is pure
  # and cheap, and a later rung's options only ever improve coverage.
  defp solve_groups(state, wanted, floor_groups, plan_prefs) do
    options = Enum.reverse(state.options)

    assignment_by_unit =
      Enum.reduce(floor_groups, %{}, fn {group_min, group_wanted}, acc ->
        solution = Planner.solve(group_wanted, options, %{plan_prefs | min_quality: group_min})

        for assignment <- solution.assignments,
            unit <- assignment.units,
            into: acc,
            do: {unit, assignment}
      end)

    %{
      state
      | assignment_by_unit: assignment_by_unit,
        residual: Enum.reject(wanted, &Map.has_key?(assignment_by_unit, &1))
    }
  end
```

(`Enum.reverse(state.options)` preserves discovery order for the singles pass's `max_by` tie-breaking — same semantics as the old `gather_options` reverse.)

**3b.** Update the moduledoc's first two paragraphs:

```elixir
  @moduledoc """
  Oban worker that runs a draft plan's autonomous search-and-solve
  phase (media-search campaign Phase 3) as a **residual-driven
  descent** of the coverage ladder.

  One run walks the rungs broad-to-narrow — series term, per-season
  terms, per-unit episode terms — but each rung is searched **only for
  the units the previous rungs' solve left uncovered** (the solver's
  residual, `Planner.Solution.unfound` unioned across quality-floor
  groups). An acceptable complete-series pack ends the run after one
  search; season packs end it before any episode term fires; only
  proven gaps pay for episode searches. Every search still goes
  through the corpus (`Corpus.search/2`, consult-first citizenship;
  `force: true` only on a user-initiated re-search), and a forced
  re-run also descends lazily — it re-hammers only as deep as the
  residual requires.

  Results are identity-verified (`TitleMatcher.coverage/2`), plan-wide
  exclusions filtered, and `Planner.solve/3` assigns candidates by the
  settled objective hierarchy. Assignments land on the plan units
  (found / unfound) and the plan transitions to `ready` for the user's
  steering pass.

  Movie plans skip the ladder: one term, best acceptable result by
  quality-then-seeders (`TitleMatcher.matches?/2` identity).

  Broadcasts `PlanEvents.SearchActivity` per term (the live activity
  feed) and `PlanEvents.Changed` when the rows move. Failures mark the
  plan's `error` and still transition to `ready` — a reported gap, not
  a stuck spinner.
  """
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `mix test test/media_centaur/acquisition/jobs/run_plan_test.exs`
Expected: PASS (5 tests)

- [ ] **Step 5: Update the lifecycle test's exclusion stub in `plans_test.exs`**

Run `mix test test/media_centaur/acquisition/plans_test.exs` first: the lifecycle test now fails at the exclusion step — under lazy descent the first run never searched the S1 episode terms (the season pack covered them), so the exclusion replan legitimately descends to the episode rung live, and `poison_searches_allow_grabs/0` raises. That raise is the *old* contract; the new contract is "broad rungs from the corpus, episode descent allowed". Replace the helper and its call site:

```elixir
  # The exclusion replan legitimately descends to the episode rung for
  # the newly-uncovered units — those terms were never searched in the
  # first pass (the pack covered them), so they aren't fresh. The
  # broad rungs MUST still come from the corpus: a series/season
  # re-search here would be the consult-first regression this guards.
  defp poison_broad_searches_allow_episode_descent do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", _path} ->
          Req.Test.json(conn, %{"approved" => true})

        {"GET", "/api/v1/search"} ->
          %{"query" => query} = URI.decode_query(conn.query_string)

          unless query =~ ~r/S\d{2}E\d{2}$/ do
            raise "broad rung searched (#{query}) despite a fresh corpus"
          end

          results =
            if query == "Sample Show S01E01" do
              [release("Sample.Show.S01E01.2160p.WEB-DL.x265", "e1-uhd", %{seeders: 8})]
            else
              []
            end

          Req.Test.json(conn, results)

        _other ->
          Req.Test.json(conn, %{})
      end
    end)
  end
```

In the lifecycle test, replace `poison_searches_allow_grabs()` with `poison_broad_searches_allow_episode_descent()` and update the comment above it:

```elixir
      # ── Steer: "not this release" on the pack. The replan re-reads
      # the fresh corpus for the broad rungs and descends live only to
      # the episode terms the first pass never needed. ──────────────────
      poison_broad_searches_allow_episode_descent()
```

Delete the now-unused `poison_searches_allow_grabs/0` (zero-warnings policy). The `stub_ladder_results/0` fixture's `"Sample Show S01E01"` entry no longer fires during the *initial* run (the pack covers S1 before the episode rung) — leave it; it documents the corpus content the original flow produced and is harmless.

All other assertions in the file stay byte-identical — the lifecycle outcome (e1-uhd assigned, 3 unfound) is unchanged.

The swap-picker test (`"the swap picker: alternatives are listed from the corpus..."`) also fails now (the corpus no longer holds episode singles after the initial run). **Leave it red** — Task 4 reworks it around `search_alternatives/1`. Mark it skipped temporarily so the tree stays green for the commit:

```elixir
    @tag :skip
    test "the swap picker: alternatives are listed from the corpus, suspicious flagged not hidden, choice reassigns" do
```

- [ ] **Step 6: Run the file and the acquisition suite**

Run: `mix test test/media_centaur/acquisition/`
Expected: PASS (1 skipped)

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur/acquisition/jobs/run_plan.ex test/media_centaur/acquisition/jobs/run_plan_test.exs test/media_centaur/acquisition/plans_test.exs
git commit -m "feat(acquisition): residual-driven descent of the coverage ladder"
```

---

### Task 3: `PlanEvents.DescentStatus` broadcasts

**Files:**
- Modify: `lib/media_centaur/acquisition/plan_events.ex`
- Modify: `lib/media_centaur/acquisition/jobs/run_plan.ex`
- Modify: `test/media_centaur/acquisition/jobs/run_plan_test.exs`

- [ ] **Step 1: Write the failing broadcast test**

Append to the `describe "residual-driven descent"` block in `run_plan_test.exs`:

```elixir
    test "the descent narrates itself — full itinerary snapshots on acquisition:updates" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.acquisition_updates())

      stub_recording_searches(%{
        "Sample Show Season 1" => [
          release("Sample.Show.S01.COMPLETE.1080p.WEB-DL", "pack-s1", %{seeders: 30})
        ],
        "Sample Show Season 2" => [
          release("Sample.Show.S02.COMPLETE.1080p.WEB-DL", "pack-s2", %{seeders: 30})
        ]
      })

      {:ok, _plan} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}, {1, 3}, {2, 1}])

      assert_received %PlanEvents.DescentStatus{wanted: 4} = series_active
      assert descent_states(series_active) == [series: :active, seasons: :pending, episodes: :pending]

      assert_received %PlanEvents.DescentStatus{} = seasons_active
      assert descent_states(seasons_active) == [series: :done, seasons: :active, episodes: :pending]

      assert_received %PlanEvents.DescentStatus{} = final
      assert descent_states(final) == [series: :done, seasons: :done, episodes: :skipped]
      assert Enum.find(final.stages, &(&1.id == :seasons)).residual_after == 0
      refute_received %PlanEvents.DescentStatus{}
    end
```

Add the helper at the bottom of the test module and the alias up top:

```elixir
  alias MediaCentaur.Acquisition.PlanEvents
```

```elixir
  defp descent_states(%PlanEvents.DescentStatus{stages: stages}) do
    Enum.map(stages, &{&1.id, &1.state})
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/media_centaur/acquisition/jobs/run_plan_test.exs`
Expected: FAIL — `PlanEvents.DescentStatus.__struct__/0 is undefined`

- [ ] **Step 3: Add the event struct**

In `lib/media_centaur/acquisition/plan_events.ex`, after `SearchActivity`:

```elixir
  defmodule DescentStatus do
    @moduledoc """
    Itinerary snapshot for the coverage-ladder descent (TV plans): every
    rung with its state, so the board can narrate what will happen,
    what's happening, and what changed. Each broadcast carries the FULL
    snapshot — subscribers replace, never merge, so a modal opened
    mid-run self-heals on the next event.
    """

    @enforce_keys [:plan_id, :wanted, :stages]
    defstruct [:plan_id, :wanted, :stages]

    @type stage :: %{
            id: :series | :seasons | :episodes,
            state: :pending | :active | :done | :skipped,
            term_count: non_neg_integer() | nil,
            residual_after: non_neg_integer() | nil
          }

    @type t :: %__MODULE__{
            plan_id: Ecto.UUID.t() | nil,
            wanted: pos_integer(),
            stages: [stage()]
          }
  end
```

And extend `event?/1` (order matters — keep the catch-all last):

```elixir
  def event?(Changed), do: true
  def event?(SearchActivity), do: true
  def event?(DescentStatus), do: true
  def event?(_module), do: false
```

- [ ] **Step 4: Broadcast from the descent loop**

In `run_plan.ex`, add a module attribute near the top of the module body:

```elixir
  @rung_ids [:series, :seasons, :episodes]
```

Rewrite the loop section of `run_tv/3` (from `initial = ...` through the `Enum.reduce_while`) to track stage summaries and broadcast:

```elixir
    initial = %{
      options: [],
      terms_by_guid: %{},
      assignment_by_unit: %{},
      residual: wanted,
      stages: []
    }

    state =
      Enum.reduce_while(rungs(plan), initial, fn {rung_id, terms_for}, state ->
        terms = terms_for.(state.residual)
        active = %{id: rung_id, state: :active, term_count: length(terms), residual_after: nil}
        broadcast_descent(plan, length(wanted), state.stages, active)

        state =
          state
          |> gather_rung(plan, terms, identity, excluded, force?)
          |> solve_groups(wanted, floor_groups, plan_prefs)

        done = %{active | state: :done, residual_after: length(state.residual)}
        state = %{state | stages: state.stages ++ [done]}

        if state.residual == [], do: {:halt, state}, else: {:cont, state}
      end)

    skipped =
      for {rung_id, _terms_for} <- rungs(plan),
          not Enum.any?(state.stages, &(&1.id == rung_id)),
          do: %{id: rung_id, state: :skipped, term_count: nil, residual_after: nil}

    broadcast_descent(plan, length(wanted), state.stages ++ skipped, nil)
```

Add the broadcaster next to `search/4`:

```elixir
  # Full itinerary snapshot: stages already walked (done/skipped), the
  # active rung if any, then the untouched rungs as pending.
  defp broadcast_descent(plan, wanted_count, walked_stages, active) do
    taken = Enum.map(walked_stages, & &1.id) ++ if active, do: [active.id], else: []

    pending =
      for rung_id <- @rung_ids,
          rung_id not in taken,
          do: %{id: rung_id, state: :pending, term_count: nil, residual_after: nil}

    status = %PlanEvents.DescentStatus{
      plan_id: plan.id,
      wanted: wanted_count,
      stages: walked_stages ++ List.wrap(active) ++ pending
    }

    Phoenix.PubSub.broadcast(MediaCentaur.PubSub, Topics.acquisition_updates(), status)
  end
```

Add to the moduledoc's final paragraph: `Broadcasts ... PlanEvents.DescentStatus per rung (the board's expectation panel), and PlanEvents.Changed when the rows move.`

- [ ] **Step 5: Run the tests**

Run: `mix test test/media_centaur/acquisition/jobs/run_plan_test.exs && mix test test/media_centaur/acquisition/`
Expected: PASS (1 skipped in plans_test)

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/acquisition/plan_events.ex lib/media_centaur/acquisition/jobs/run_plan.ex test/media_centaur/acquisition/jobs/run_plan_test.exs
git commit -m "feat(acquisition): descent itinerary broadcasts (PlanEvents.DescentStatus)"
```

---

### Task 4: `Plans.search_alternatives/1`

**Files:**
- Modify: `lib/media_centaur/acquisition/plans.ex`
- Modify: `test/media_centaur/acquisition/plans_test.exs` (un-skip + rework the swap-picker test)

- [ ] **Step 1: Rework the swap-picker test (failing)**

Remove the `@tag :skip` from Task 2 and reshape the test body. The setup stub stays exactly as it is (it already serves `"Sample Show S01E01"` with the clean 4K single and the bait release). Replace the body from `{:ok, plan} = ...` down:

```elixir
      {:ok, plan} = Plans.create_series_plan(selection(), [{1, 1}, {1, 2}, {1, 3}])
      {:ok, plan} = Plans.get(plan.id)
      assert plan.status == "ready"

      units = Plans.units_for(plan.id)
      assert Enum.all?(units, &(&1.assigned_guid == "pack-s1"))

      [first_unit | _rest] = units

      # The descent stopped at the season rung, so the corpus holds
      # nothing deeper — the picker starts honest and empty.
      assert {:ok, []} = Plans.alternatives_for(first_unit.id)

      # "Find more" live-fills exactly the unit's never-searched terms.
      {:ok, alternatives} = Plans.search_alternatives(first_unit.id)

      # Clean candidate first; the bait visible but flagged and sorted
      # last — and it was never auto-picked despite 999 seeders.
      assert [clean, evil] = alternatives
      assert clean.guid == "e1-uhd"
      refute clean.suspicious?
      assert clean.size_bytes == 2_400_000_000
      assert evil.guid == "e1-evil"
      assert evil.suspicious?

      # Consult-first: a second find-more is served entirely from the
      # now-fresh corpus — zero indexer traffic.
      Req.Test.stub(:prowlarr, fn conn ->
        case conn.method do
          "POST" -> Req.Test.json(conn, %{"approved" => true})
          method -> raise "indexer searched (#{method}) despite a fresh corpus"
        end
      end)

      assert {:ok, again} = Plans.search_alternatives(first_unit.id)
      assert Enum.map(again, & &1.guid) == Enum.map(alternatives, & &1.guid)

      # Deliberate choice reassigns exactly the units the choice covers.
      assert {:ok, _plan} = Plans.choose_release(first_unit.id, "e1-uhd")

      units = Plans.units_for(plan.id)
      chosen_unit = Enum.find(units, &(&1.episode_number == 1))
      assert chosen_unit.assigned_guid == "e1-uhd"
      assert chosen_unit.assigned_size_bytes == 2_400_000_000
      assert Enum.find(units, &(&1.episode_number == 2)).assigned_guid == "pack-s1"
      assert Enum.find(units, &(&1.episode_number == 3)).assigned_guid == "pack-s1"
```

Update the test name to match the new contract:

```elixir
    test "the swap picker: find-more live-fills the unit's terms consult-first, suspicious flagged not hidden, choice reassigns" do
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/media_centaur/acquisition/plans_test.exs`
Expected: FAIL — `Plans.search_alternatives/1 is undefined`

- [ ] **Step 3: Implement `search_alternatives/1`**

In `lib/media_centaur/acquisition/plans.ex`, directly below `alternatives_for/1` (the `Corpus` and `LadderTerms` aliases already exist in this module):

```elixir
  @doc """
  The swap picker's "find more" action: live-fills the corpus for the
  unit's ladder terms (consult-first — fresh terms cost nothing; terms
  the descent never reached go to the indexer), then returns the
  refreshed alternatives. Individual search failures are skipped, not
  raised — the picker shows whatever the corpus knows.
  """
  @spec search_alternatives(Ecto.UUID.t()) ::
          {:ok, [PlanBoard.Alternative.t()]} | {:error, :not_found}
  def search_alternatives(plan_unit_id) do
    with {:ok, unit} <- get_unit(plan_unit_id),
         {:ok, plan} <- get(unit.plan_id) do
      plan
      |> LadderTerms.for_unit(unit)
      |> Enum.each(fn {term, opts} ->
        Corpus.search(term, Keyword.take(opts, [:type, :year]))
      end)

      alternatives_for(plan_unit_id)
    end
  end
```

- [ ] **Step 4: Run the file, then the acquisition suite**

Run: `mix test test/media_centaur/acquisition/plans_test.exs && mix test test/media_centaur/acquisition/`
Expected: PASS, 0 skipped

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/plans.ex test/media_centaur/acquisition/plans_test.exs
git commit -m "feat(acquisition): on-demand find-more search for the swap picker"
```

---

### Task 5: `DescentNarrative` view-model

**Files:**
- Create: `lib/media_centaur/acquisition/view_models/descent_narrative.ex`
- Create: `test/media_centaur/acquisition/view_models/descent_narrative_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule MediaCentaur.Acquisition.ViewModels.DescentNarrativeTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.PlanEvents.DescentStatus
  alias MediaCentaur.Acquisition.ViewModels.DescentNarrative

  defp stage(id, state, attrs \\ []) do
    %{
      id: id,
      state: state,
      term_count: Keyword.get(attrs, :term_count),
      residual_after: Keyword.get(attrs, :residual_after)
    }
  end

  defp status(stages, wanted), do: %DescentStatus{plan_id: "plan-1", wanted: wanted, stages: stages}

  test "initial/1 narrates the strategy before any event lands" do
    view = DescentNarrative.initial(24)

    assert view.headline ==
             "Planning the search — broadest releases first, drilling down only for what's still missing."

    assert Enum.map(view.rows, &{&1.id, &1.state}) ==
             [series: :pending, seasons: :pending, episodes: :pending]

    assert Enum.map(view.rows, & &1.label) ==
             ["Complete series", "Season packs", "Individual episodes"]
  end

  test "an active rung headlines what's happening with the live residual" do
    view =
      DescentNarrative.build(
        status(
          [
            stage(:series, :done, residual_after: 4),
            stage(:seasons, :active, term_count: 4),
            stage(:episodes, :pending)
          ],
          24
        )
      )

    assert view.headline == "Now searching season packs — 4 episodes still need coverage…"
    assert Enum.find(view.rows, &(&1.id == :seasons)).detail == "searching — 4 terms…"
  end

  test "a done rung's detail says what it changed" do
    view =
      DescentNarrative.build(
        status(
          [
            stage(:series, :done, residual_after: 24),
            stage(:seasons, :done, residual_after: 1),
            stage(:episodes, :active, term_count: 1)
          ],
          24
        )
      )

    rows = Map.new(view.rows, &{&1.id, &1.detail})
    assert rows[:series] == "nothing usable found"
    assert rows[:seasons] == "covered 23 episodes — 1 still missing"
    assert view.headline == "Now hunting individual episodes — 1 episode still uncovered…"
  end

  test "a finished descent with skipped rungs explains the early stop" do
    view =
      DescentNarrative.build(
        status(
          [
            stage(:series, :done, residual_after: 24),
            stage(:seasons, :done, residual_after: 0),
            stage(:episodes, :skipped)
          ],
          24
        )
      )

    assert view.headline == "Everything covered — the deeper searches weren't needed."
    assert Enum.find(view.rows, &(&1.id == :episodes)).detail == "not needed — already covered"
    assert Enum.find(view.rows, &(&1.id == :seasons)).detail == "covered everything that was left"
  end

  test "a finished descent with leftovers reports the gap" do
    view =
      DescentNarrative.build(
        status(
          [
            stage(:series, :done, residual_after: 4),
            stage(:seasons, :done, residual_after: 2),
            stage(:episodes, :done, residual_after: 2)
          ],
          4
        )
      )

    assert view.headline == "Search finished — 2 episodes couldn't be found anywhere."
    assert Enum.find(view.rows, &(&1.id == :episodes)).detail == "nothing usable found"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/media_centaur/acquisition/view_models/descent_narrative_test.exs`
Expected: FAIL — module undefined

- [ ] **Step 3: Implement the view-model**

Create `lib/media_centaur/acquisition/view_models/descent_narrative.ex`:

```elixir
defmodule MediaCentaur.Acquisition.ViewModels.DescentNarrative do
  @moduledoc """
  The plan board's expectation panel: renders a
  `PlanEvents.DescentStatus` snapshot into a headline (what's
  happening / what changed) plus one row per ladder rung (what to
  expect from it). Pure — the LiveView only assigns the built view
  (ADR-030). `initial/1` covers the moment before the first broadcast
  lands, so the board narrates the strategy from its first paint.
  """

  alias MediaCentaur.Acquisition.PlanEvents.DescentStatus

  defmodule Row do
    @moduledoc "One ladder rung in the expectation panel."

    @enforce_keys [:id, :state, :label, :detail]
    defstruct [:id, :state, :label, :detail]

    @type t :: %__MODULE__{
            id: :series | :seasons | :episodes,
            state: :pending | :active | :done | :skipped,
            label: String.t(),
            detail: String.t()
          }
  end

  defmodule View do
    @moduledoc "The built panel: headline plus rung rows."

    @enforce_keys [:headline, :rows]
    defstruct [:headline, :rows]

    @type t :: %__MODULE__{headline: String.t(), rows: [Row.t()]}
  end

  @pending_stages [
    %{id: :series, state: :pending, term_count: nil, residual_after: nil},
    %{id: :seasons, state: :pending, term_count: nil, residual_after: nil},
    %{id: :episodes, state: :pending, term_count: nil, residual_after: nil}
  ]

  @doc "The pre-event itinerary — expectations before the first broadcast."
  @spec initial(pos_integer()) :: View.t()
  def initial(wanted) do
    build(%DescentStatus{plan_id: nil, wanted: wanted, stages: @pending_stages})
  end

  @doc "Renders one full snapshot into the panel view."
  @spec build(DescentStatus.t()) :: View.t()
  def build(%DescentStatus{} = status) do
    %View{headline: headline(status), rows: rows(status)}
  end

  # -- headline ---------------------------------------------------------------

  defp headline(%DescentStatus{stages: stages, wanted: wanted}) do
    cond do
      active = Enum.find(stages, &(&1.state == :active)) ->
        active_headline(active.id, residual_before_active(stages, wanted))

      Enum.all?(stages, &(&1.state == :pending)) ->
        "Planning the search — broadest releases first, drilling down only for what's still missing."

      true ->
        finished_headline(stages)
    end
  end

  defp active_headline(:series, _residual),
    do: "First, looking for one release that covers the whole show…"

  defp active_headline(:seasons, residual),
    do: "Now searching season packs — #{count(residual, "episode")} still need coverage…"

  defp active_headline(:episodes, residual),
    do: "Now hunting individual episodes — #{count(residual, "episode")} still uncovered…"

  defp finished_headline(stages) do
    last_done = stages |> Enum.filter(&(&1.state == :done)) |> List.last()
    skipped? = Enum.any?(stages, &(&1.state == :skipped))

    case {last_done, skipped?} do
      {%{residual_after: 0}, true} -> "Everything covered — the deeper searches weren't needed."
      {%{residual_after: 0}, false} -> "Everything covered."
      {%{residual_after: missing}, _} -> "Search finished — #{count(missing, "episode")} couldn't be found anywhere."
      {nil, _} -> "Search finished."
    end
  end

  defp residual_before_active(stages, wanted) do
    stages
    |> Enum.take_while(&(&1.state != :active))
    |> Enum.filter(&(&1.state == :done))
    |> List.last()
    |> case do
      nil -> wanted
      %{residual_after: residual} -> residual
    end
  end

  # -- rows -------------------------------------------------------------------

  defp rows(%DescentStatus{stages: stages, wanted: wanted}) do
    stages
    |> Enum.map_reduce(wanted, fn stage, residual_before ->
      row = %Row{
        id: stage.id,
        state: stage.state,
        label: label(stage.id),
        detail: detail(stage, residual_before)
      }

      {row, stage.residual_after || residual_before}
    end)
    |> elem(0)
  end

  defp label(:series), do: "Complete series"
  defp label(:seasons), do: "Season packs"
  defp label(:episodes), do: "Individual episodes"

  defp detail(%{state: :pending, id: :series}, _residual),
    do: "one search for an all-in-one release"

  defp detail(%{state: :pending, id: :seasons}, _residual),
    do: "packs for whatever the series rung leaves uncovered"

  defp detail(%{state: :pending, id: :episodes}, _residual),
    do: "single episodes, only for what's still missing"

  defp detail(%{state: :active, term_count: terms}, _residual),
    do: "searching — #{count(terms, "term")}…"

  defp detail(%{state: :done, residual_after: 0}, _residual),
    do: "covered everything that was left"

  defp detail(%{state: :done, residual_after: still_missing}, residual_before) do
    case residual_before - still_missing do
      0 -> "nothing usable found"
      covered -> "covered #{count(covered, "episode")} — #{still_missing} still missing"
    end
  end

  defp detail(%{state: :skipped}, _residual), do: "not needed — already covered"

  defp count(1, noun), do: "1 #{noun}"
  defp count(quantity, noun), do: "#{quantity} #{noun}s"
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/media_centaur/acquisition/view_models/descent_narrative_test.exs`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/view_models/descent_narrative.ex test/media_centaur/acquisition/view_models/descent_narrative_test.exs
git commit -m "feat(acquisition): DescentNarrative view-model for the expectation panel"
```

---

### Task 6: Find-more button (picker UI)

**Files:**
- Modify: `lib/media_centaur_web/live/acquisition_live.ex`
- Modify: `lib/media_centaur_web/components/acquisition/plan_modal.ex`
- Modify: `storybook/acquisition/plan_modal.story.exs`
- Modify: `test/media_centaur_web/live/acquisition_live_test.exs`

- [ ] **Step 1: Rework the failing swap-picker UI test**

In `acquisition_live_test.exs`, the test `"the swap picker: Options lists corpus alternatives; choosing reassigns the unit"` now finds an empty picker (descent stopped at the season rung). Rename it to `"the swap picker: find-more live-fills alternatives; choosing reassigns the unit"` and replace the body after `render_click()` on the Options button:

```elixir
      view
      |> element("button[phx-click='plan_show_alternatives'][phx-value-unit-id='#{unit.id}']")
      |> render_click()

      # The descent never searched episode terms — the picker starts empty.
      html = render(view)
      assert html =~ "Nothing else in the corpus yet"
      refute html =~ "Sample.Show.S01E01.2160p.WEB-DL.x265"

      view
      |> element("button[phx-click='plan_find_more_alternatives'][phx-value-unit-id='#{unit.id}']")
      |> render_click()

      html = render_async(view)
      assert html =~ "Sample.Show.S01E01.2160p.WEB-DL.x265"
      assert html =~ "None of these"

      view
      |> element("button[phx-click='plan_choose_release'][phx-value-guid='ui-uhd']")
      |> render_click()

      _ = render(view)

      reloaded = plan.id |> Plans.units_for() |> Enum.find(&(&1.id == unit.id))
      assert reloaded.assigned_guid == "ui-uhd"
```

(The test's existing Prowlarr stub already serves `"Sample Show S01E01"` — no stub change.)

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/media_centaur_web/live/acquisition_live_test.exs`
Expected: FAIL — no `plan_find_more_alternatives` element

- [ ] **Step 3: Wire the LiveView**

In `acquisition_live.ex`:

**3a.** `plan_show_alternatives` (around line 817) gains the `searching?` key so the assign shape is uniform:

```elixir
  def handle_event("plan_show_alternatives", %{"unit-id" => unit_id}, socket) do
    case Plans.alternatives_for(unit_id) do
      {:ok, items} ->
        {:noreply,
         assign(socket, plan_alternatives: %{unit_id: unit_id, items: items, searching?: false})}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end
```

**3b.** New event directly below it. `start_async` (owned async, MC0019) — the search must not block the LiveView:

```elixir
  def handle_event("plan_find_more_alternatives", %{"unit-id" => unit_id}, socket) do
    case socket.assigns.plan_alternatives do
      %{unit_id: ^unit_id} = open ->
        {:noreply,
         socket
         |> assign(plan_alternatives: Map.put(open, :searching?, true))
         |> start_async(:plan_find_more, fn -> {unit_id, Plans.search_alternatives(unit_id)} end)}

      _other ->
        {:noreply, socket}
    end
  end
```

**3c.** `handle_async` clauses, placed with the other `handle_async` callbacks:

```elixir
  def handle_async(:plan_find_more, {:ok, {unit_id, result}}, socket) do
    case {result, socket.assigns.plan_alternatives} do
      {{:ok, items}, %{unit_id: ^unit_id}} ->
        {:noreply,
         assign(socket, plan_alternatives: %{unit_id: unit_id, items: items, searching?: false})}

      {_result, %{unit_id: ^unit_id} = open} ->
        {:noreply, assign(socket, plan_alternatives: Map.put(open, :searching?, false))}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_async(:plan_find_more, {:exit, reason}, socket) do
    Log.warning(:acquisition, "find-more alternatives crashed — #{inspect(reason)}")

    case socket.assigns.plan_alternatives do
      %{} = open -> {:noreply, assign(socket, plan_alternatives: Map.put(open, :searching?, false))}
      _other -> {:noreply, socket}
    end
  end
```

- [ ] **Step 4: Add the button to `alternatives_panel`**

In `plan_modal.ex`:

**4a.** Update the empty-state copy (line ~581):

```heex
      <p :if={@alternatives.items == []} class="text-xs text-base-content/40 py-1">
        Nothing else in the corpus yet — Find more runs this episode's searches.
      </p>
```

**4b.** In the panel's footer row, add the Find-more button *before* "None of these — re-solve":

```heex
        <.button
          variant="neutral"
          size="xs"
          phx-click="plan_find_more_alternatives"
          phx-value-unit-id={@alternatives.unit_id}
          disabled={@alternatives[:searching?] == true}
          title="Search the indexers for more options for this span"
          data-nav-item
          tabindex="0"
        >
          <span :if={@alternatives[:searching?]} class="loading loading-spinner loading-xs"></span>
          {if @alternatives[:searching?], do: "Searching…", else: "Find more"}
        </.button>
```

(`@alternatives[:searching?]` — Access, not dot — so story fixtures without the key still render.)

**4c.** Update the two `alternatives` attr docs (lines ~62 and ~398) to
`"%{unit_id, items: [PlanBoard.Alternative.t()], searching?: boolean} | nil — the open swap picker (board stage)."`

- [ ] **Step 5: Story variation (MC0009)**

In `plan_modal.story.exs`, add after `:board_alternatives_open`:

```elixir
      %Variation{
        id: :board_alternatives_searching,
        description:
          "Find-more in flight — the button shows progress and ignores clicks; already-known candidates stay put.",
        attributes: %{
          open: true,
          stage: :board,
          board: board(:ready),
          alternatives: %{
            unit_id: "story-unit-1-1",
            searching?: true,
            items: [
              %PlanBoard.Alternative{
                guid: "alt-single",
                title: "Sample.Show.S01E01.1080p.WEB-DL.x264",
                scope_label: "S01E01",
                quality: "1080p",
                seeders: 41,
                size_bytes: 2_100_000_000
              }
            ]
          },
          last_activity: "Searched: Sample Show S01E01 — 1 found"
        }
      },
```

- [ ] **Step 6: Run the tests**

Run: `mix test test/media_centaur_web/live/acquisition_live_test.exs && mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur_web/live/acquisition_live.ex lib/media_centaur_web/components/acquisition/plan_modal.ex storybook/acquisition/plan_modal.story.exs test/media_centaur_web/live/acquisition_live_test.exs
git commit -m "feat(acquisition): find-more button in the swap picker"
```

---

### Task 7: Descent narration panel (board UI)

**Files:**
- Modify: `lib/media_centaur_web/live/acquisition_live.ex`
- Modify: `lib/media_centaur_web/components/acquisition/plan_modal.ex`
- Modify: `storybook/acquisition/plan_modal.story.exs`
- Modify: `test/media_centaur_web/live/acquisition_live_test.exs`

- [ ] **Step 1: Write the failing LiveView test**

Add to the plan-board describe block in `acquisition_live_test.exs` (alias `MediaCentaur.Acquisition.PlanEvents` at the top of the file if not present):

```elixir
    test "the board narrates the descent as status events land", %{conn: conn} do
      stub_plan_tmdb()

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)

            results =
              if query == "Sample Show Season 1" do
                [
                  %{
                    "title" => "Sample.Show.S01.COMPLETE.1080p.WEB-DL",
                    "guid" => "ui-pack",
                    "indexerId" => 1,
                    "seeders" => 30,
                    "indexer" => "indexer-a"
                  }
                ]
              else
                []
              end

            Req.Test.json(conn, results)

          _other ->
            Req.Test.json(conn, %{})
        end
      end)

      {:ok, plan} = Plans.create_series_plan(stub_selection(), [{1, 1}, {1, 2}])

      {:ok, view, _html} = live_async!(conn, ~p"/download?plan=#{plan.id}")

      send(view.pid, %PlanEvents.DescentStatus{
        plan_id: plan.id,
        wanted: 2,
        stages: [
          %{id: :series, state: :done, term_count: 1, residual_after: 2},
          %{id: :seasons, state: :done, term_count: 2, residual_after: 0},
          %{id: :episodes, state: :skipped, term_count: nil, residual_after: nil}
        ]
      })

      html = render(view)
      assert html =~ "Everything covered — the deeper searches weren&#39;t needed."
      assert html =~ "not needed — already covered"

      # A status for some other plan must not clobber the open board's panel.
      send(view.pid, %PlanEvents.DescentStatus{
        plan_id: Ecto.UUID.generate(),
        wanted: 9,
        stages: [
          %{id: :series, state: :active, term_count: 1, residual_after: nil},
          %{id: :seasons, state: :pending, term_count: nil, residual_after: nil},
          %{id: :episodes, state: :pending, term_count: nil, residual_after: nil}
        ]
      })

      html = render(view)
      assert html =~ "Everything covered — the deeper searches weren&#39;t needed."
    end
```

(Apostrophes render HTML-escaped — assert with `&#39;` as shown, matching how other tests in this file assert copy with quotes; check neighbours and follow suit.)

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/media_centaur_web/live/acquisition_live_test.exs`
Expected: FAIL — the narration copy never renders

- [ ] **Step 3: Wire the LiveView**

In `acquisition_live.ex`:

**3a.** Alias at the top with the other acquisition aliases:

```elixir
  alias MediaCentaur.Acquisition.ViewModels.DescentNarrative
```

**3b.** Mount assigns (~line 163, next to `plan_last_activity: nil`): add `plan_descent: nil`.

**3c.** `apply_plan_modal_params/2`'s `nil` branch (~line 1680): add `plan_descent: nil` to the assign list.

**3d.** `open_plan_board/2` (~line 1758) — seed expectations when the board is mid-planning; never clobber a live-updated panel on the `Changed`-event reload path:

```elixir
  defp open_plan_board(socket, plan_id) do
    case Plans.get(plan_id) do
      {:ok, plan} ->
        board = Plans.board_for(plan)

        assign(socket,
          plan_param: plan_id,
          plan_stage: :board,
          plan_board: board,
          plan_descent: plan_descent_for(socket, plan_id, board),
          plan_error: nil
        )

      {:error, :not_found} ->
        assign(socket,
          plan_param: plan_id,
          plan_stage: :error,
          plan_error: "Plan not found — it may have been discarded."
        )
    end
  end

  # Keep a live-updated panel across board reloads; seed the itinerary
  # for a freshly-opened planning board; movies don't narrate.
  defp plan_descent_for(socket, plan_id, board) do
    cond do
      socket.assigns.plan_param == plan_id && socket.assigns.plan_descent ->
        socket.assigns.plan_descent

      board.status == :planning and not board.movie? ->
        DescentNarrative.initial(board.wanted)

      true ->
        nil
    end
  end
```

**3e.** `handle_info/2` cond (~line 1301) — add a branch after the `SearchActivity` one:

```elixir
      struct == PlanEvents.DescentStatus ->
        {:noreply, maybe_note_plan_descent(socket, event)}
```

And the helper next to `maybe_note_plan_activity/2`:

```elixir
  defp maybe_note_plan_descent(socket, %PlanEvents.DescentStatus{} = status) do
    if socket.assigns.plan_param == status.plan_id do
      assign(socket, plan_descent: DescentNarrative.build(status))
    else
      socket
    end
  end
```

**3f.** Pass the assign into the modal (~line 462, next to `last_activity={@plan_last_activity}`): add `descent={@plan_descent}`.

- [ ] **Step 4: Render the panel in `plan_modal.ex`**

**4a.** Public attr after `:last_activity` (~line 58):

```elixir
  attr :descent, :any,
    default: nil,
    doc: "%DescentNarrative.View{} | nil — the board's expectation panel (TV plans)."
```

**4b.** Pass through to `board_stage` (~line 100): add `descent={@descent}` to the `<.board_stage>` call, and to `board_stage`'s attrs (~line 403):

```elixir
  attr :descent, :any, required: true, doc: "%DescentNarrative.View{} | nil — typed at the public attr."
```

**4c.** Render between the title block (`</div>` closing at ~line 424) and the season-grid `<div :if={!@board.movie?}>`:

```heex
        <div :if={@descent} class="glass-inset rounded-lg px-3 py-2 space-y-1.5">
          <p class="text-sm text-base-content/70">{@descent.headline}</p>
          <div :for={row <- @descent.rows} class="flex items-center gap-2 text-xs">
            <span class={["size-1.5 rounded-full flex-shrink-0", descent_dot(row.state)]}></span>
            <span class={[
              "w-32 flex-shrink-0 text-base-content/60",
              row.state == :skipped && "line-through text-base-content/30"
            ]}>
              {row.label}
            </span>
            <span class="min-w-0 truncate text-base-content/40">{row.detail}</span>
          </div>
        </div>
```

**4d.** Private helper at the bottom of the module, next to `format_size/1`:

```elixir
  defp descent_dot(:active), do: "bg-info animate-pulse"
  defp descent_dot(:done), do: "bg-success/70"
  defp descent_dot(_pending_or_skipped), do: "bg-base-content/20"
```

(The pulse matches the board's existing "dashed/pulsing" searching-cell language; color carries progress state only — consistent with the no-decorative-color rule.)

- [ ] **Step 5: Story variation (MC0009)**

In `plan_modal.story.exs`, add the alias and extend `:board_planning`:

```elixir
  alias MediaCentaur.Acquisition.ViewModels.DescentNarrative
```

In the `:board_planning` variation's attributes, add:

```elixir
          descent: %DescentNarrative.View{
            headline: "Now searching season packs — 2 episodes still need coverage…",
            rows: [
              %DescentNarrative.Row{
                id: :series,
                state: :done,
                label: "Complete series",
                detail: "nothing usable found"
              },
              %DescentNarrative.Row{
                id: :seasons,
                state: :active,
                label: "Season packs",
                detail: "searching — 4 terms…"
              },
              %DescentNarrative.Row{
                id: :episodes,
                state: :pending,
                label: "Individual episodes",
                detail: "single episodes, only for what's still missing"
              }
            ]
          },
```

And update that variation's description to mention the expectation panel:

```elixir
        description:
          "Mid-flight — the expectation panel narrates the descent (done/active/pending rungs), dashed searching cells, the activity ticker, no spinner-only state.",
```

- [ ] **Step 6: Run the web tests**

Run: `mix test test/media_centaur_web/live/acquisition_live_test.exs && mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs && mix test test/media_centaur_web/page_smoke_test.exs`
Expected: PASS (no new route — the smoke run is a regression guard for the `/download` template change)

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur_web/live/acquisition_live.ex lib/media_centaur_web/components/acquisition/plan_modal.ex storybook/acquisition/plan_modal.story.exs test/media_centaur_web/live/acquisition_live_test.exs
git commit -m "feat(acquisition): descent expectation panel on the plan board"
```

---

### Task 8: Ship — precommit, wiki, wrap-up

- [ ] **Step 1: Full precommit**

Run: `mix precommit`
Expected: clean — zero warnings, credo --strict, boundaries, sobelow, full suite green. Fix anything it reports (formatting will likely touch the new files; `git add -u` and amend the last commit if so).

- [ ] **Step 2: Wiki sync (user-visible changes)**

In `~/src/media-centaur/media-centaur.wiki`, update the page documenting the plan board / downloads flow (locate with `grep -rl "plan board\|Options" .`; likely a *Using Media Centaur* page) plus `FAQ.md`:

- Plan board: describe the expectation panel — the search runs broadest-first (complete series → season packs → individual episodes) and only drills down for episodes still uncovered, so big shows no longer fan out hundreds of searches; the panel narrates each step and says when deeper steps were skipped.
- Swap picker: "Options" starts from what the planner already searched; **Find more** runs that episode's own searches on demand (cheap — already-fresh searches are reused).
- FAQ entry: "Why does the picker sometimes start empty?" → because the descent stopped early; Find more fills it.

```bash
cd ~/src/media-centaur/media-centaur.wiki
git add -A && git commit -m "wiki: residual-driven plan search + find-more picker" && git push
```

- [ ] **Step 3: Confirm the working tree**

Run: `git -C ~/src/media-centaur/media-centaur-app status` and `git log --oneline -8`
Expected: clean tree; the task commits present on `main`. Do **not** push — the user decides when to ship.

---

## Self-Review (run after writing, fix inline)

1. **Spec coverage** — descent loop (Task 2), rung constructors + invariant (Task 1), per-floor residual (Task 2 test 5), force-lazy (covered by descent loop passing `force?` through unchanged), DescentStatus broadcasts (Task 3), narration copy + initial paint (Tasks 5/7), find-more seam + consult-first (Task 4) + button/async (Task 6), MC0009 stories (Tasks 6/7), deliberate test-contract updates (Tasks 2/4/6). Out-of-scope items have no tasks — correct.
2. **Placeholders** — none; every step carries the code or the exact command.
3. **Type consistency** — `stage` maps use `%{id, state, term_count, residual_after}` everywhere (RunPlan broadcasts, DescentStatus type, narrative input, tests); the picker assign is `%{unit_id, items, searching?}` in LiveView, component, and story; `search_alternatives/1` returns `alternatives_for/1`'s shape.
