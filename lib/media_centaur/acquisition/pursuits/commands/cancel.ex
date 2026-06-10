defmodule MediaCentaur.Acquisition.Pursuits.Commands.Cancel do
  @moduledoc """
  Closes a pursuit by user request — cancels every still-active unit
  and refolds the parent (ADR-055; a pursuit with satisfied units
  folds to `partial`, one with none folds to `cancelled`). Cancels
  every in-flight target so snoozed `PursueTarget` Oban jobs
  early-exit on their next wake, and records the `pursuit_cancelled`
  event.

  After the transaction commits, the cancelled targets' downloads are
  removed from the download client (with their partial data — the
  content is unwanted): a cancelled pursuit must not mint orphans
  (campaign pursuit-identity-and-lifecycle). Client I/O is
  best-effort — a failure is logged and never blocks the cancel; the
  Other-downloads zone remains the safety net.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Pursuits.Commands.{Refold, Runner}
  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.PursuitCancelled
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, State, Unit, Units}
  alias MediaCentaur.Acquisition.Targets
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Repo

  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, cancelled_by: by, reason: reason})
      when is_atom(by) and is_binary(reason) do
    # Read before the transaction flips target statuses to "cancelled".
    in_flight_hashes = Targets.in_flight_hashes(id)

    result =
      Runner.run(id, "pursuit cancelled", fn pursuit ->
        with true <- pursuit.state in State.in_flight() || {:error, :not_eligible},
             {:ok, _units} <- cancel_active_units(pursuit),
             {:ok, refolded, _transition} <- Refold.refold!(pursuit),
             :ok <- Targets.close_in_flight_for(refolded.id, nil, "pursuit_cancelled"),
             {:ok, _event} <-
               Events.record(%PursuitCancelled{
                 pursuit_id: refolded.id,
                 pursuit_title: refolded.title,
                 occurred_at: DateTime.utc_now(:second),
                 cancelled_by: Atom.to_string(by),
                 reason: reason
               }) do
          {:ok, refolded}
        end
      end)

    with {:ok, pursuit} <- result do
      if by == :user, do: dismiss_tracking_wants(pursuit)
      stop_client_downloads(pursuit, in_flight_hashes)
      {:ok, pursuit}
    end
  end

  # Post-transaction, best-effort: remove each cancelled target's
  # download from the client. Hash-keyed and driver-neutral
  # (`Acquisition.cancel_download/1` dispatches to the configured
  # driver); an unconfigured client degrades to a no-op.
  defp stop_client_downloads(_pursuit, []), do: :ok

  defp stop_client_downloads(pursuit, hashes) do
    Enum.each(hashes, fn hash ->
      case MediaCentaur.Acquisition.cancel_download(hash) do
        :ok ->
          Log.info(
            :acquisition,
            "cancelled pursuit download — #{pursuit.title} (#{String.slice(hash, 0, 10)})"
          )

        {:error, reason} ->
          Log.warning(
            :acquisition,
            "could not stop a cancelled pursuit's download — " <>
              "#{pursuit.title} (#{String.slice(hash, 0, 10)}): #{inspect(reason)}"
          )
      end
    end)
  end

  # ADR-056 Q5: a *user* cancelling a tracking-born pursuit means "stop
  # wanting these units" — the covered wants are dismissed, so the next
  # cadence tick does not re-plan them. System cancels (stalls, pivots,
  # migrations) leave the wants open: the intent survives the attempt.
  defp dismiss_tracking_wants(pursuit) do
    case Plans.tracking_item_id_for_pursuit(pursuit.id) do
      nil ->
        :ok

      item_id ->
        unit_keys =
          pursuit.id
          |> Units.for_pursuit()
          |> Enum.map(fn unit ->
            ReleaseTracking.Want.unit_key(
              unit.season_number,
              unit.episode_number,
              movie_part_id(pursuit)
            )
          end)
          |> Enum.reject(&is_nil/1)

        ReleaseTracking.dismiss_want_units(item_id, unit_keys)
        :ok
    end
  end

  defp movie_part_id(%Pursuit{tmdb_type: "movie", tmdb_id: tmdb_id}) when is_binary(tmdb_id) do
    case Integer.parse(tmdb_id) do
      {part_id, ""} -> part_id
      _ -> nil
    end
  end

  defp movie_part_id(_pursuit), do: nil

  defp cancel_active_units(pursuit) do
    pursuit.id
    |> Units.active_for()
    |> Enum.reduce_while({:ok, []}, fn unit, {:ok, cancelled} ->
      case Repo.update(Unit.cancel_changeset(unit)) do
        {:ok, updated} -> {:cont, {:ok, [updated | cancelled]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end
end
