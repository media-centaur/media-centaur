defmodule MediaCentaur.Acquisition.TrackingHandoffs do
  @moduledoc """
  The two media-search → release-tracking handoffs (ADR-056 Phase 3 /
  media-search campaign Phase 4):

  * **Grab future** — a plan approved with the `grab_future` opt-in
    spins up a tracking item when its pursuit *completes* (folds to
    `satisfied`, every selected unit landed — never on `partial`).
    Deferred to completion by design so the track and the pursuit never
    contend over the same units.
  * **Gap handoff** — "found 9 of 10": the units a ready plan couldn't
    find become gap-provenance wants on a (created if needed) tracking
    item, so the cadence keeps watching for them politely.

  Both handoffs are idempotent: tracking items are unique per
  `(tmdb_id, media_type)` and the want ledger refuses duplicate unit
  keys. Failures are logged, never raised — a TMDB hiccup must not
  break the satisfy/approval flows that trigger these.
  """

  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Plans.{Plan, PlanUnit}
  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Repo
  alias MediaCentaur.TMDB.Title

  @doc """
  Runs the grab-future handoff for a pursuit that just refolded.
  No-op unless the pursuit is terminal-`satisfied` and its plan
  carries the opt-in.
  """
  @spec maybe_grab_future(Pursuit.t()) :: :ok
  def maybe_grab_future(%Pursuit{state: "satisfied", recipe_type: "tmdb"} = pursuit) do
    grab_future? =
      Plan
      |> where([p], p.pursuit_id == ^pursuit.id and p.grab_future == true)
      |> Repo.exists?()

    if grab_future? do
      case ensure_tracked(pursuit.tmdb_id, pursuit.tmdb_type, pursuit.title) do
        {:ok, item} ->
          Log.info(:acquisition, "grab-future handoff — now tracking #{item.name}")

        {:error, reason} ->
          Log.warning(
            :acquisition,
            "grab-future handoff failed — #{pursuit.title} — #{inspect(reason)}"
          )
      end
    end

    :ok
  end

  def maybe_grab_future(%Pursuit{}), do: :ok

  @doc """
  Tracks a ready plan's gaps: every `unfound` unit becomes a
  gap-provenance want on the title's tracking item (created when the
  title isn't tracked yet). Returns `{:ok, opened_count}`.
  """
  @spec track_plan_gaps(Ecto.UUID.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def track_plan_gaps(plan_id) do
    with %Plan{} = plan <- Repo.get(Plan, plan_id) || {:error, :not_found},
         [_ | _] = gaps <- unfound_units(plan.id),
         {:ok, item} <- ensure_tracked(plan.tmdb_id, plan.tmdb_type, plan.title) do
      specs = Enum.map(gaps, &gap_spec(plan, &1))
      opened = ReleaseTracking.open_gap_wants(item, specs)

      Log.info(
        :acquisition,
        "gap handoff — watching for #{opened} of #{length(gaps)} gaps on #{plan.title}"
      )

      {:ok, opened}
    else
      [] -> {:ok, 0}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fire-and-forget `track_plan_gaps/1` on a supervised context-layer
  task (ADR-049) — the gap handoff does a TMDB fetch when the title
  isn't tracked yet, which doesn't belong inline in a LiveView event.
  """
  @spec track_plan_gaps_async(Ecto.UUID.t()) :: :ok
  def track_plan_gaps_async(plan_id) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      track_plan_gaps(plan_id)
    end)

    :ok
  end

  defp unfound_units(plan_id) do
    PlanUnit
    |> where([u], u.plan_id == ^plan_id and u.status == "unfound")
    |> order_by([u], asc: u.position)
    |> Repo.all()
  end

  defp gap_spec(%Plan{tmdb_type: "movie"} = plan, unit) do
    %{part_tmdb_id: String.to_integer(plan.tmdb_id), title: unit.label}
  end

  defp gap_spec(%Plan{}, unit) do
    %{season_number: unit.season_number, episode_number: unit.episode_number, title: unit.label}
  end

  defp ensure_tracked(tmdb_id, tmdb_type, title) do
    tmdb_id_int = String.to_integer(tmdb_id)
    media_type = media_type_for(tmdb_type)

    case ReleaseTracking.get_item_by_tmdb(tmdb_id_int, media_type) do
      nil ->
        ReleaseTracking.track_from_search(
          Title.new!(%{tmdb_id: tmdb_id_int, media_type: media_type, name: title})
        )

      item ->
        {:ok, item}
    end
  end

  defp media_type_for("tv"), do: :tv_series
  defp media_type_for("movie"), do: :movie
end
