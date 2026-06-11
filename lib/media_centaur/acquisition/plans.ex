defmodule MediaCentaur.Acquisition.Plans do
  @moduledoc """
  The durable draft plan context (media-search campaign Phase 3):
  creation from a targeting selection, the feedback verbs the user
  steers with (exclude a release, exclude a unit, force a re-plan),
  and approval/discard. The autonomous search-and-solve lives in
  `Acquisition.Jobs.RunPlan`; commit-to-pursuit in
  `Plans.Commands.CommitPlan`.

  Every mutation broadcasts `PlanEvents.Changed` on
  `acquisition:updates` so live surfaces re-read; the rows themselves
  are the state of record (durable draft — refresh-safe by design).
  """

  import Ecto.Query

  alias MediaCentaur.Acquisition.Jobs.RunPlan
  alias MediaCentaur.Acquisition.PlanEvents
  alias MediaCentaur.Acquisition.Corpus
  alias MediaCentaur.Acquisition.Plans.{CommitPlan, LadderTerms, Plan, PlanUnit}
  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.Acquisition.ViewModels.PlanBoard
  alias MediaCentaur.Search.{Criteria, Quality, ReleaseCoverage, ReleaseRedFlags, TitleMatcher}
  alias MediaCentaur.Repo
  alias MediaCentaur.Topics

  @type unit_choice :: {pos_integer(), pos_integer()}

  @doc """
  Creates a draft plan for a series selection and the user's chosen
  units, then starts the autonomous planning run. Units carry their
  picker labels so the board reads like the picker did.
  """
  @spec create_series_plan(Targeting.Selection.t(), [unit_choice()], keyword()) ::
          {:ok, Plan.t()} | {:error, term()}
  def create_series_plan(%Targeting.Selection{} = selection, unit_choices, opts \\ []) do
    labels =
      for season <- selection.seasons, episode <- season.episodes, into: %{} do
        {{episode.season_number, episode.episode_number}, episode.label}
      end

    unit_specs =
      unit_choices
      |> Enum.with_index()
      |> Enum.map(fn {{season, episode}, index} ->
        %{
          season_number: season,
          episode_number: episode,
          label: unit_label(season, episode, Map.get(labels, {season, episode})),
          position: index
        }
      end)

    create_plan(
      %{
        tmdb_id: selection.tmdb_id,
        tmdb_type: "tv",
        title: selection.title,
        criteria: Keyword.get(opts, :criteria, %{}),
        grab_future: Keyword.get(opts, :grab_future, false)
      },
      unit_specs
    )
  end

  @doc "Creates a single-unit movie plan and starts the planning run."
  @spec create_movie_plan(map(), keyword()) :: {:ok, Plan.t()} | {:error, term()}
  def create_movie_plan(%{tmdb_id: tmdb_id, title: title} = attrs, opts \\ []) do
    create_plan(
      %{
        tmdb_id: to_string(tmdb_id),
        tmdb_type: "movie",
        title: title,
        year: Map.get(attrs, :year),
        criteria: Keyword.get(opts, :criteria, %{}),
        grab_future: Keyword.get(opts, :grab_future, false)
      },
      [%{season_number: nil, episode_number: nil, label: title, position: 0}]
    )
  end

  @doc """
  Creates a release-tracking drop plan (ADR-056 Phase 2) and starts the
  planning run. `plan_attrs` carries the tmdb identity plus
  `tracking_item_id`; `unit_specs` come from the item's due wants and
  may carry per-unit `min_quality` floors (the patience elevation,
  stamped by the drop planner so the planner stays time-blind).
  """
  @spec create_tracking_plan(map(), [map()]) :: {:ok, Plan.t()} | {:error, term()}
  def create_tracking_plan(plan_attrs, unit_specs) do
    plan_attrs
    |> Map.put_new(:origin, "tracking")
    |> create_plan(unit_specs)
  end

  @doc """
  Whether a live tracking draft (planning or ready) already exists for
  this tmdb identity — the one-active-draft-per-title rule (ADR-056
  Q2): wants opening mid-draft wait for the next tick rather than
  mutating a plan under review.
  """
  @spec active_tracking_draft?(String.t(), String.t()) :: boolean()
  def active_tracking_draft?(tmdb_id, tmdb_type) do
    Plan
    |> where([p], p.origin == "tracking" and p.status in ["planning", "ready"])
    |> where([p], p.tmdb_id == ^tmdb_id and p.tmdb_type == ^tmdb_type)
    |> Repo.exists?()
  end

  @doc """
  The tracking item id behind a committed pursuit, when the pursuit was
  born from a plan carrying tracking provenance — the cancel-dismisses
  back-pointer. Covers both automated drop plans (origin "tracking")
  and user-initiated "plan now" drafts (origin "manual" with a
  tracking_item_id). Nil for plain media-search and legacy pursuits.
  """
  @spec tracking_item_id_for_pursuit(Ecto.UUID.t()) :: Ecto.UUID.t() | nil
  def tracking_item_id_for_pursuit(pursuit_id) do
    Plan
    |> where([p], p.pursuit_id == ^pursuit_id and not is_nil(p.tracking_item_id))
    |> select([p], p.tracking_item_id)
    |> limit(1)
    |> Repo.one()
  end

  defp create_plan(plan_attrs, unit_specs) do
    if unit_specs == [] do
      {:error, :no_units}
    else
      result =
        Repo.transaction(fn ->
          with {:ok, plan} <- Repo.insert(Plan.create_changeset(plan_attrs)),
               :ok <- insert_units(plan, unit_specs) do
            plan
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

      with {:ok, plan} <- result do
        Oban.insert(RunPlan.new(%{"plan_id" => plan.id}))
        broadcast_changed(plan)
        {:ok, plan}
      end
    end
  end

  defp insert_units(plan, unit_specs) do
    Enum.reduce_while(unit_specs, :ok, fn spec, :ok ->
      case Repo.insert(PlanUnit.create_changeset(Map.put(spec, :plan_id, plan.id))) do
        {:ok, _unit} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp unit_label(season, episode, nil), do: "S#{pad(season)}E#{pad(episode)}"
  defp unit_label(season, episode, title), do: "S#{pad(season)}E#{pad(episode)} · #{title}"

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  # ---------------------------------------------------------------------------
  # Reads
  # ---------------------------------------------------------------------------

  @spec get(Ecto.UUID.t()) :: {:ok, Plan.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Plan, id) do
      nil -> {:error, :not_found}
      %Plan{} = plan -> {:ok, plan}
    end
  end

  @doc "The plan's units in display order."
  @spec units_for(Ecto.UUID.t()) :: [PlanUnit.t()]
  def units_for(plan_id) do
    PlanUnit
    |> where([u], u.plan_id == ^plan_id)
    |> order_by([u], asc: u.position, asc: u.inserted_at)
    |> Repo.all()
  end

  @doc """
  Builds the `PlanBoard` view-model for the coverage board (UIDR-014):
  unit cells in season rows, the chosen releases grouped from the
  units' assignments, and the gaps. One units query.
  """
  @spec board_for(Plan.t()) :: PlanBoard.t()
  def board_for(%Plan{} = plan) do
    units = units_for(plan.id)
    planning? = plan.status == "planning"

    cells =
      Enum.map(units, fn unit ->
        %PlanBoard.Cell{
          plan_unit_id: unit.id,
          season_number: unit.season_number,
          episode_number: unit.episode_number,
          label: unit.label,
          state: cell_state(unit.status, planning?),
          release_guid: unit.assigned_guid,
          release_title: unit.assigned_title
        }
      end)

    seasons =
      cells
      |> Enum.group_by(& &1.season_number)
      |> Enum.sort_by(fn {season, _cells} -> season || 0 end)
      |> Enum.map(fn {season, season_cells} ->
        %PlanBoard.SeasonRow{
          season_number: season,
          cells: Enum.sort_by(season_cells, & &1.episode_number)
        }
      end)

    releases =
      units
      |> Enum.filter(&(&1.status == "found"))
      |> Enum.group_by(& &1.assigned_guid)
      |> Enum.map(fn {guid, group} ->
        [first | _] = Enum.sort_by(group, & &1.position)

        %PlanBoard.Release{
          guid: guid,
          title: first.assigned_title,
          scope_label: first.assigned_scope,
          quality: first.assigned_quality,
          seeders: first.assigned_seeders,
          size_bytes: first.assigned_size_bytes,
          units_count: length(group),
          swap_unit_id: first.id
        }
      end)
      |> Enum.sort_by(&(-&1.units_count))

    wanted = Enum.count(units, &(&1.status != "excluded"))
    covered = Enum.count(units, &(&1.status == "found"))

    %PlanBoard{
      plan_id: plan.id,
      title: plan.title,
      status: String.to_existing_atom(plan.status),
      error: plan.error,
      wanted: wanted,
      covered: covered,
      seasons: seasons,
      releases: releases,
      gaps: units |> Enum.filter(&(&1.status == "unfound")) |> Enum.map(& &1.label),
      total_size_bytes: total_size(releases),
      movie?: plan.tmdb_type == "movie"
    }
  end

  defp total_size(releases) do
    sizes = releases |> Enum.map(& &1.size_bytes) |> Enum.filter(&is_integer/1)
    if sizes != [], do: Enum.sum(sizes)
  end

  defp cell_state("found", _planning?), do: :assigned
  defp cell_state("unfound", _planning?), do: :unfound
  defp cell_state("excluded", _planning?), do: :excluded
  defp cell_state("pending", true), do: :searching
  defp cell_state("pending", false), do: :unfound

  @doc "Draft plans still in flight (planning or ready), newest first."
  @spec list_drafts() :: [Plan.t()]
  def list_drafts do
    Plan
    |> where([p], p.status in ["planning", "ready"])
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # The swap picker (UIDR-014 follow-up): see the options, choose one.
  # ---------------------------------------------------------------------------

  @doc """
  The choosable alternatives for one plan unit — corpus candidates
  across the unit's ladder terms (zero indexer traffic), identity-
  verified, covering the unit, minus exclusions and the current
  assignment. Suspicious (bait-pattern) titles are **flagged, not
  hidden** — never auto-picked, but a deliberate human may choose one.
  Sorted: clean before suspicious, then quality, then seeders.
  """
  @spec alternatives_for(Ecto.UUID.t()) ::
          {:ok, [PlanBoard.Alternative.t()]} | {:error, :not_found}
  def alternatives_for(plan_unit_id) do
    with {:ok, unit} <- get_unit(plan_unit_id),
         {:ok, plan} <- get(unit.plan_id) do
      excluded = MapSet.new(unit.excluded_release_guids)

      alternatives =
        plan
        |> unit_candidates(unit)
        |> Enum.reject(fn {result, _scope} ->
          result.guid == unit.assigned_guid or MapSet.member?(excluded, result.guid)
        end)
        |> Enum.map(fn {result, scope} ->
          %PlanBoard.Alternative{
            guid: result.guid,
            title: result.title,
            scope_label: scope_display(scope),
            quality: Quality.label(result.quality),
            seeders: result.seeders,
            size_bytes: result.size_bytes,
            suspicious?: ReleaseRedFlags.suspicious?(result.title, result.size_bytes)
          }
        end)
        |> Enum.sort_by(&{&1.suspicious?, -quality_rank(&1.quality), -(&1.seeders || 0)})
        |> Enum.take(12)

      {:ok, alternatives}
    end
  end

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

  @doc """
  Deliberately assigns a corpus candidate to a unit (the swap picker's
  choice). The candidate claims **every** non-excluded plan unit its
  scope covers — accounting stays per-unit total — and the plan
  broadcasts. Only `ready` plans accept choices.
  """
  @spec choose_release(Ecto.UUID.t(), String.t()) :: {:ok, Plan.t()} | {:error, term()}
  def choose_release(plan_unit_id, guid) when is_binary(guid) do
    with {:ok, unit} <- get_unit(plan_unit_id),
         {:ok, %Plan{status: "ready"} = plan} <- ready_plan(unit.plan_id),
         {:ok, {result, scope, term}} <- find_candidate(plan, unit, guid) do
      covered_units =
        plan.id
        |> units_for()
        |> Enum.filter(fn candidate_unit ->
          candidate_unit.status != "excluded" and covers_unit?(plan, scope, candidate_unit, unit)
        end)

      attrs = %{
        assigned_guid: result.guid,
        assigned_title: result.title,
        assigned_term: term,
        assigned_quality: Quality.label(result.quality),
        assigned_seeders: result.seeders,
        assigned_size_bytes: result.size_bytes,
        assigned_scope: scope_display(scope)
      }

      {:ok, _} =
        Repo.transaction(fn ->
          Enum.each(covered_units, fn covered ->
            {:ok, _} = Repo.update(PlanUnit.assign_changeset(covered, attrs))
          end)
        end)

      broadcast_changed(plan)
      {:ok, plan}
    else
      {:ok, %Plan{}} -> {:error, :not_ready}
      error -> error
    end
  end

  defp ready_plan(plan_id) do
    get(plan_id)
  end

  # All identity-verified corpus candidates that can cover this unit,
  # as {result, scope} pairs (movies carry the :movie pseudo-scope).
  defp unit_candidates(plan, unit) do
    plan
    |> LadderTerms.for_unit(unit)
    |> Enum.flat_map(fn {term, opts} ->
      term
      |> Corpus.candidates_for(Keyword.take(opts, [:type, :year]))
      |> Enum.map(&{term, &1})
    end)
    |> Enum.uniq_by(fn {_term, result} -> result.guid end)
    |> Enum.flat_map(fn {term, result} ->
      case verify(plan, unit, result) do
        {:ok, scope} -> [{result, scope, term}]
        :no_match -> []
      end
    end)
    |> Enum.map(fn {result, scope, _term} -> {result, scope} end)
  end

  defp find_candidate(plan, unit, guid) do
    plan
    |> LadderTerms.for_unit(unit)
    |> Enum.find_value({:error, :alternative_unavailable}, fn {term, opts} ->
      candidate =
        term
        |> Corpus.candidates_for(Keyword.take(opts, [:type, :year]))
        |> Enum.find(&(&1.guid == guid))

      with %{} <- candidate,
           {:ok, scope} <- verify(plan, unit, candidate) do
        {:ok, {candidate, scope, term}}
      else
        _ -> nil
      end
    end)
  end

  defp verify(%Plan{tmdb_type: "movie"} = plan, _unit, result) do
    criteria = %Criteria{type: :tmdb, title: plan.title, tmdb_type: :movie, year: plan.year}
    if TitleMatcher.matches?(result, criteria), do: {:ok, :movie}, else: :no_match
  end

  defp verify(%Plan{tmdb_type: "tv"} = plan, unit, result) do
    criteria = %Criteria{type: :tmdb, title: plan.title, tmdb_type: :tv}

    with {:ok, scope} <- TitleMatcher.coverage(result, criteria),
         true <- ReleaseCoverage.covers?(scope, unit.season_number, unit.episode_number) do
      {:ok, scope}
    else
      _ -> :no_match
    end
  end

  defp covers_unit?(%Plan{tmdb_type: "movie"}, :movie, candidate_unit, chosen_unit),
    do: candidate_unit.id == chosen_unit.id

  defp covers_unit?(_plan, scope, candidate_unit, _chosen_unit) do
    ReleaseCoverage.covers?(scope, candidate_unit.season_number, candidate_unit.episode_number)
  end

  defp scope_display(:movie), do: nil
  defp scope_display({:episode, season, episode}), do: "S#{pad(season)}E#{pad(episode)}"

  defp scope_display({:episodes, season, first, last}), do: "S#{pad(season)}E#{pad(first)}-#{pad(last)}"

  defp scope_display({:season, season}), do: "Season #{season} pack"
  defp scope_display({:seasons, first, last}), do: "Seasons #{first}–#{last} pack"
  defp scope_display(:series), do: "Complete series"
  defp scope_display(:unknown), do: nil

  defp quality_rank("4K"), do: 2
  defp quality_rank("1080p"), do: 1
  defp quality_rank(_quality), do: 0

  # ---------------------------------------------------------------------------
  # Feedback verbs
  # ---------------------------------------------------------------------------

  @doc """
  "Not this release" for one unit: records the exclusion, resets the
  unit to pending, and re-plans from the corpus (no forced re-search —
  swapping resolves among already-known candidates first).
  """
  @spec exclude_release(Ecto.UUID.t(), String.t()) :: {:ok, Plan.t()} | {:error, term()}
  def exclude_release(plan_unit_id, guid) do
    with {:ok, unit} <- get_unit(plan_unit_id),
         {:ok, plan} <- get(unit.plan_id),
         {:ok, _unit} <- Repo.update(PlanUnit.exclude_release_changeset(unit, guid)) do
      replan(plan)
    end
  end

  @doc "User opt-out of one unit — the plan stops wanting it."
  @spec exclude_unit(Ecto.UUID.t()) :: {:ok, Plan.t()} | {:error, term()}
  def exclude_unit(plan_unit_id) do
    with {:ok, unit} <- get_unit(plan_unit_id),
         {:ok, plan} <- get(unit.plan_id),
         {:ok, _unit} <- Repo.update(PlanUnit.exclude_unit_changeset(unit)) do
      replan(plan)
    end
  end

  @doc """
  Forces a fresh planning pass. `force_search: true` bypasses the
  corpus freshness gate (the user-initiated "search again").
  """
  @spec replan(Plan.t(), keyword()) :: {:ok, Plan.t()} | {:error, term()}
  def replan(%Plan{} = plan, opts \\ []) do
    with {:ok, planning} <-
           Repo.update(Plan.transition_changeset(plan, "planning", ["planning", "ready"])) do
      Oban.insert(
        RunPlan.new(%{"plan_id" => planning.id, "force" => Keyword.get(opts, :force_search, false)})
      )

      broadcast_changed(planning)
      {:ok, planning}
    end
  end

  @doc "Commits a ready plan as one composite pursuit. See `CommitPlan`."
  @spec approve(Plan.t()) :: {:ok, Plan.t()} | {:error, term()}
  def approve(%Plan{} = plan), do: CommitPlan.execute(plan)

  @doc "Discards a draft plan (terminal; rows are kept for the record)."
  @spec discard(Plan.t()) :: {:ok, Plan.t()} | {:error, term()}
  def discard(%Plan{} = plan) do
    with {:ok, discarded} <-
           Repo.update(Plan.transition_changeset(plan, "discarded", ["planning", "ready"])) do
      broadcast_changed(discarded)
      {:ok, discarded}
    end
  end

  @doc """
  Deletes a tracking draft outright — used by the mode gate when a drop
  plan solves to zero found units. Unlike user-facing discards there is
  no record value in an automated tick that found nothing (the wants
  remain the durable intent, stamped searched), and the cadence would
  otherwise accrete discarded rows every interval an unfound want
  retries.
  """
  @spec delete_tracking_draft(Plan.t()) :: :ok
  def delete_tracking_draft(%Plan{origin: "tracking"} = plan) do
    Repo.delete_all(where(PlanUnit, [u], u.plan_id == ^plan.id))
    Repo.delete_all(where(Plan, [p], p.id == ^plan.id))
    broadcast_changed(%{plan | status: "discarded"})
    :ok
  end

  defp get_unit(plan_unit_id) do
    case Repo.get(PlanUnit, plan_unit_id) do
      nil -> {:error, :not_found}
      %PlanUnit{} = unit -> {:ok, unit}
    end
  end

  @doc "Broadcasts `PlanEvents.Changed` for the plan on `acquisition:updates`."
  @spec broadcast_changed(Plan.t()) :: :ok
  def broadcast_changed(%Plan{} = plan) do
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      Topics.acquisition_updates(),
      %PlanEvents.Changed{plan_id: plan.id, status: plan.status}
    )

    :ok
  end
end
