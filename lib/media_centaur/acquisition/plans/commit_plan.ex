defmodule MediaCentaur.Acquisition.Plans.CommitPlan do
  @moduledoc """
  Commits a `ready` draft plan as **one composite pursuit** — the
  approval gate of the plan-before-pursue lifecycle (media-search
  campaign Phase 3). Nothing grabs until this runs.

  ## The overlap check (ADR-055 identity)

  Before anything is created, the invariant *no two active pursuers
  may claim the same unit of the same title* is enforced: every found
  unit is intersected against active TMDB pursuits' claimed units
  (unit-level season/episode, falling back to the legacy pursuit-level
  key for single-unit auto pursuits). Any intersection rejects the
  commit with `{:error, {:overlap, units}}` — the user resolves it at
  the plan, not by racing two pursuers.

  ## What gets created

  Only **found** units become pursuit units — unfound units are search
  results, never pursuit leaves (the campaign's hard boundary), and
  excluded units were opted out. Assignments grouped by release become
  the leaves: per group, the candidate is rehydrated from the corpus
  and grabbed at Prowlarr; a successful grab lands as an `acquired`
  target covering every unit of its group, a failed grab degrades that
  group to `seeking` targets per unit so the regular `PursueTarget`
  machinery takes over (the plan's promise survives an indexer
  hiccup). The plan is stamped `committed` with the pursuit id as
  provenance.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Corpus
  alias MediaCentaur.Acquisition.Jobs.PursueTarget
  alias MediaCentaur.Acquisition.PlanEvents
  alias MediaCentaur.Acquisition.Plans.{Claims, Plan, PlanUnit}
  alias MediaCentaur.Acquisition.Pursuits.Commands.Start
  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.ReleasePicked
  alias MediaCentaur.Acquisition.Pursuits.{TargetUnit, Unit, Units}
  alias MediaCentaur.Acquisition.{InfoHash, Target}
  alias MediaCentaur.Repo
  alias MediaCentaur.Search.{Prowlarr, SearchResult}
  alias MediaCentaur.Topics

  import Ecto.Query

  @spec execute(Plan.t()) :: {:ok, Plan.t()} | {:error, term()}
  def execute(%Plan{status: "ready"} = plan) do
    found_units =
      plan.id
      |> plan_units()
      |> Enum.filter(&(&1.status == "found"))

    with :ok <- ensure_grabbable(found_units),
         :ok <- ensure_no_overlap(plan, found_units),
         {:ok, pursuit} <- create_pursuit(plan, found_units) do
      grab_assignments(pursuit, found_units)

      {:ok, committed} = Repo.update(Plan.committed_changeset(plan, pursuit.id))
      broadcast(committed)
      Log.info(:acquisition, "plan committed — #{plan.title} → pursuit #{pursuit.id}")
      {:ok, committed}
    end
  end

  def execute(%Plan{}), do: {:error, :not_ready}

  defp ensure_grabbable([]), do: {:error, :nothing_to_grab}
  defp ensure_grabbable(_found_units), do: :ok

  # ---------------------------------------------------------------------------
  # Overlap check — the ADR-055 identity invariant, generalized.
  # ---------------------------------------------------------------------------

  defp ensure_no_overlap(%Plan{tmdb_type: "movie"} = plan, _units) do
    if Claims.movie_pursuit_claimed?(plan.tmdb_id) do
      {:error, {:overlap, [{nil, nil}]}}
    else
      :ok
    end
  end

  defp ensure_no_overlap(%Plan{tmdb_type: "tv"} = plan, units) do
    wanted = MapSet.new(units, &{&1.season_number, &1.episode_number})
    claimed = Claims.pursuit_claimed_units(plan.tmdb_id)

    MapSet.intersection(wanted, claimed)
    |> MapSet.to_list()
    |> case do
      [] -> :ok
      overlapping -> {:error, {:overlap, Enum.sort(overlapping)}}
    end
  end

  # ---------------------------------------------------------------------------
  # Creation
  # ---------------------------------------------------------------------------

  defp create_pursuit(plan, found_units) do
    unit_specs =
      Enum.map(found_units, fn unit ->
        %{
          label: unit.label,
          season_number: unit.season_number,
          episode_number: unit.episode_number,
          position: unit.position
        }
      end)

    Start.execute(%{
      recipe_type: "tmdb",
      tmdb_id: plan.tmdb_id,
      tmdb_type: plan.tmdb_type,
      title: plan.title,
      year: plan.year,
      origin_country: plan.origin_country,
      origin: pursuit_origin(plan),
      criteria: plan.criteria,
      units: unit_specs
    })
  end

  # Tracking-born pursuits keep the "auto" origin the rest of the app
  # already understands (filters, cards); media-search commits stay
  # "manual" user acts.
  defp pursuit_origin(%Plan{origin: "tracking"}), do: "auto"
  defp pursuit_origin(%Plan{}), do: "manual"

  defp grab_assignments(pursuit, found_units) do
    pursuit_units = Units.for_pursuit(pursuit.id)

    units_by_key =
      Map.new(pursuit_units, fn unit -> {{unit.season_number, unit.episode_number}, unit} end)

    found_units
    |> Enum.group_by(& &1.assigned_guid)
    |> Enum.each(fn {guid, group} ->
      covered_units =
        group
        |> Enum.map(&Map.get(units_by_key, {&1.season_number, &1.episode_number}))
        |> Enum.reject(&is_nil/1)

      result = rehydrate(hd(group))

      case Prowlarr.grab(result) do
        :ok ->
          land_acquired(pursuit, result, covered_units)

        {:error, reason} ->
          Log.warning(
            :acquisition,
            "plan grab failed — #{result.title} — #{inspect(reason)}; degrading to seeking"
          )

          degrade_to_seeking(pursuit, covered_units)
      end

      guid
    end)
  end

  # The corpus is the rehydration source (full grab-ready struct);
  # the denormalized assignment fields are the fallback when the
  # candidate aged out of retention between ready and approve.
  defp rehydrate(%PlanUnit{} = unit) do
    corpus_hit =
      unit.assigned_term &&
        unit.assigned_term
        |> Corpus.candidates_for(type: :tv)
        |> Enum.find(&(&1.guid == unit.assigned_guid))

    corpus_hit ||
      unit.assigned_term
      |> Corpus.candidates_for([])
      |> Enum.find(&(&1.guid == unit.assigned_guid)) ||
      %SearchResult{
        title: unit.assigned_title,
        guid: unit.assigned_guid,
        indexer_id: unit.assigned_indexer_id,
        seeders: unit.assigned_seeders
      }
  end

  defp land_acquired(pursuit, result, covered_units) do
    now = DateTime.utc_now(:second)
    torrent_hash = InfoHash.resolve(result)

    {:ok, target} =
      result
      |> Target.acquired_changeset(
        pursuit_id: pursuit.id,
        origin: pursuit.origin,
        torrent_hash: torrent_hash
      )
      |> Repo.insert()

    Enum.each(covered_units, fn unit ->
      {:ok, _coverage} =
        Repo.insert(TargetUnit.create_changeset(%{target_id: target.id, unit_id: unit.id}))

      {:ok, attempted} = Repo.update(Unit.record_attempt_changeset(unit, result.guid))
      {:ok, _} = Repo.update(Unit.set_current_target_changeset(attempted, target.id))
    end)

    {:ok, _event} =
      Events.record(%ReleasePicked{
        pursuit_id: pursuit.id,
        pursuit_title: pursuit.title,
        occurred_at: now,
        release_title: result.title,
        guid: result.guid,
        indexer: result.indexer_name,
        quality: MediaCentaur.Search.Quality.label(result.quality),
        size_bytes: result.size_bytes
      })
  end

  defp degrade_to_seeking(pursuit, covered_units) do
    Enum.each(covered_units, fn unit ->
      {:ok, target} =
        %{pursuit_id: pursuit.id, title: pursuit.title, origin: pursuit.origin}
        |> Target.create_changeset()
        |> Repo.insert()

      {:ok, _coverage} =
        Repo.insert(TargetUnit.create_changeset(%{target_id: target.id, unit_id: unit.id}))

      {:ok, _} = Repo.update(Unit.set_current_target_changeset(unit, target.id))
      Oban.insert(PursueTarget.new(%{"target_id" => target.id}))
    end)
  end

  defp plan_units(plan_id) do
    PlanUnit
    |> where([u], u.plan_id == ^plan_id)
    |> order_by([u], asc: u.position)
    |> Repo.all()
  end

  defp broadcast(plan) do
    Topics.publish(
      Topics.acquisition_updates(),
      %PlanEvents.Changed{plan_id: plan.id, status: plan.status}
    )
  end
end
