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
  alias MediaCentaur.Acquisition.Plans.{CommitPlan, Plan, PlanUnit}
  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.Acquisition.ViewModels.PlanBoard
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
      movie?: plan.tmdb_type == "movie"
    }
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
