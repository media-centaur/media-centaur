defmodule MediaCentaur.Acquisition.Pursuits.IdentityVerifier do
  @moduledoc """
  Post-ingest landing satisfier for TMDB-recipe pursuits.

  Triggered by `Pursuits.InboundListener` when the pipeline publishes
  an entity for an active pursuit. Identity is already settled by the
  time this worker runs: the listener only dispatches when the
  published entity's TMDB id matches the pursuit's recipe, and the job
  args carry the landed unit (season + episode for TV). **Provenance
  over filenames** (campaign: pursuit-identity-and-lifecycle) — this
  worker never re-derives identity from the release name; the
  filename-matching gate that once lived here cancelled a whole
  composite pursuit because a non-lead unit landed first.

  Behaviour per landing:

    * **Unit wanted and open** → record `:identity_verified` and
      dispatch `Commands.Satisfy` scoped to the landed unit (its
      current target's covered span — a pack landing satisfies the
      units the pack was grabbed for). The pursuit folds terminal only
      when every unit has concluded (`Refold`).
    * **Unit not wanted / already terminal** → no-op. A landing for an
      episode the plan never asked for is library content, not a
      pursuit signal; a duplicate landing changes nothing.
    * **No unit identity in args** (legacy queued job, season-only
      publish) → no-op; `LibraryReconciler` owns the catch-up per tick.

  The worker exits silently when the pursuit no longer exists or is
  already terminal. Mismatch-style cancellation is retired here;
  `prowlarr_query` pursuits never reach this worker (the listener keys
  on TMDB identity) and are reconciled by `LibraryReconciler`'s
  release-name fallback.
  """

  use Oban.Worker, queue: :acquisition, unique: [period: 60, keys: [:pursuit_id, :file_path]]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Pursuits
  alias MediaCentaur.Acquisition.Pursuits.{Events, Pursuit, State, Unit, UnitState, Units}
  alias MediaCentaur.Acquisition.Pursuits.Commands.Satisfy
  alias MediaCentaur.Acquisition.Pursuits.Events.IdentityVerified
  alias MediaCentaur.Format

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"pursuit_id" => pursuit_id, "file_path" => file_path} = args}) do
    with {:ok, pursuit} <- load_active_pursuit(pursuit_id),
         {:ok, unit} <- landed_unit(pursuit, args) do
      satisfy_unit(pursuit, unit, file_path)
    end

    :ok
  end

  defp load_active_pursuit(pursuit_id) do
    case Pursuits.get(pursuit_id) do
      {:ok, %Pursuit{state: state} = pursuit} ->
        if State.terminal?(state), do: :skip, else: {:ok, pursuit}

      {:error, :not_found} ->
        :skip
    end
  end

  # Resolves which of the pursuit's units this landing concludes. TV
  # landings carry season + episode from the published entity; movies
  # have a single unit. Anything unresolvable is deferred to the
  # LibraryReconciler safety net rather than guessed.
  defp landed_unit(%Pursuit{tmdb_type: "tv"} = pursuit, %{
         "season_number" => season,
         "episode_number" => episode
       })
       when is_integer(season) and is_integer(episode) do
    pursuit.id
    |> Units.for_pursuit()
    |> Enum.find(&(&1.season_number == season and &1.episode_number == episode))
    |> case do
      nil ->
        Log.info(
          :acquisition,
          "landing ignored — #{pursuit.title} has no unit for " <>
            "#{Format.episode_label(season, episode)}"
        )

        :skip

      %Unit{state: state} = unit ->
        if UnitState.terminal?(state), do: :skip, else: {:ok, unit}
    end
  end

  defp landed_unit(%Pursuit{tmdb_type: "tv"} = pursuit, _args) do
    Log.info(
      :acquisition,
      "landing without unit identity — deferring #{pursuit.title} to the library reconciler"
    )

    :skip
  end

  defp landed_unit(%Pursuit{} = pursuit, _args) do
    case Units.lead(pursuit.id) do
      nil -> :skip
      %Unit{state: state} = unit -> if UnitState.terminal?(state), do: :skip, else: {:ok, unit}
    end
  end

  defp satisfy_unit(pursuit, unit, file_path) do
    Log.info(
      :acquisition,
      "landing verified — #{pursuit.title} #{unit_label(unit)} (#{Path.basename(file_path)})"
    )

    {:ok, _event} =
      Events.record(%IdentityVerified{
        pursuit_id: pursuit.id,
        pursuit_title: pursuit.title,
        occurred_at: DateTime.utc_now(:second),
        file_path: file_path
      })

    Satisfy.execute(%{
      pursuit_id: pursuit.id,
      final_target_id: unit.current_target_id,
      final_release_title: Path.basename(file_path),
      fallback_unit_id: unit.id
    })
  end

  defp unit_label(%Unit{season_number: season, episode_number: episode})
       when is_integer(season) and is_integer(episode) do
    Format.episode_label(season, episode)
  end

  defp unit_label(_unit), do: ""
end
