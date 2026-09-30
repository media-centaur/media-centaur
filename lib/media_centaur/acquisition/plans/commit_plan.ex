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
  the leaves: per group, the candidate is rehydrated from the corpus and
  written as one **grabbing** target covering every unit of its group
  (`Targets.start_grabbing/4`), whose `Jobs.GrabTarget` hands it to
  Prowlarr. The plan is stamped `committed` with the pursuit id as
  provenance.

  All of it — the checks, the pursuit, the grabbing targets with their
  jobs, the stamp — is one transaction (campaign durable-work, G1): the
  approval is recorded before anything is grabbed, a crash leaves either
  nothing or the whole commitment, and no HTTP request runs here, so a
  person's approve is a plain write. A grab Prowlarr refuses searches
  again per unit (`GrabTarget`), the fallback the plan used to take
  inline.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Corpus
  alias MediaCentaur.Acquisition.PlanEvents
  alias MediaCentaur.Acquisition.Plans.{Claims, Plan, PlanUnit, SearchOrder}
  alias MediaCentaur.Acquisition.Pursuits.Commands.Start
  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.ReleasePicked
  alias MediaCentaur.Acquisition.Pursuits.Units
  alias MediaCentaur.Acquisition.Targets
  alias MediaCentaur.Repo
  alias MediaCentaur.Search.SearchResult
  alias MediaCentaur.Topics

  import Ecto.Query

  @spec execute(Plan.t()) :: {:ok, Plan.t()} | {:error, term()}
  def execute(%Plan{status: "ready"} = plan) do
    found_units =
      plan.id
      |> plan_units()
      |> Enum.filter(&(&1.status == "found"))

    result =
      Repo.transaction(fn ->
        with :ok <- ensure_grabbable(found_units),
             :ok <- ensure_no_overlap(plan, found_units),
             {:ok, pursuit} <- create_pursuit(plan, found_units),
             :ok <- choose_releases(plan, pursuit, found_units),
             {:ok, committed} <- Repo.update(Plan.committed_changeset(plan, pursuit.id)) do
          committed
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    with {:ok, committed} <- result do
      broadcast(committed)
      Log.info(:acquisition, "plan committed — #{plan.title} → pursuit #{committed.pursuit_id}")
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
      identity: Plan.identity(plan),
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

  # One grabbing target per release group, covering the group's units, and
  # the pick recorded on the pursuit's timeline.
  defp choose_releases(%Plan{} = plan, pursuit, found_units) do
    pursuit_units = Units.for_pursuit(pursuit.id)
    units_by_key = Map.new(pursuit_units, &{{&1.season_number, &1.episode_number}, &1})

    found_units
    |> Enum.group_by(& &1.assigned_guid)
    |> Enum.reduce_while(:ok, fn {_guid, group}, :ok ->
      covered_units =
        group
        |> Enum.map(&Map.get(units_by_key, {&1.season_number, &1.episode_number}))
        |> Enum.reject(&is_nil/1)

      case choose(pursuit, rehydrate(plan, hd(group)), covered_units) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp choose(pursuit, release, covered_units) do
    with {:ok, _target} <- Targets.start_grabbing(pursuit, release, covered_units),
         {:ok, _event} <-
           Events.record(%ReleasePicked{
             pursuit_id: pursuit.id,
             pursuit_title: pursuit.title,
             occurred_at: DateTime.utc_now(:second),
             release_title: release.title,
             guid: release.guid,
             indexer: release.indexer_name,
             quality: MediaCentaur.Search.Quality.label(release.quality),
             size_bytes: release.size_bytes
           }) do
      :ok
    end
  end

  # The corpus row the assignment came from (`assigned_term` is its key)
  # is the rehydration source — the full grab-ready struct with infohash,
  # size and protocol. The denormalized assignment fields are the fallback
  # when the candidate aged out of retention between ready and approve.
  defp rehydrate(%Plan{} = plan, %PlanUnit{} = unit) do
    opts = SearchOrder.search_opts(plan)

    corpus_hit =
      case unit.assigned_term do
        nil ->
          nil

        term ->
          term |> Corpus.candidates_for(opts) |> Enum.find(&(&1.guid == unit.assigned_guid))
      end

    corpus_hit ||
      %SearchResult{
        title: unit.assigned_title,
        guid: unit.assigned_guid,
        indexer_id: unit.assigned_indexer_id,
        seeders: unit.assigned_seeders
      }
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
