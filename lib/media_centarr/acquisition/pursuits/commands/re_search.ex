defmodule MediaCentarr.Acquisition.Pursuits.Commands.ReSearch do
  @moduledoc """
  Forces a fresh `SearchAndGrab` cycle for an Active pursuit.

  - `:snoozed` grab → break the snooze, preserve `attempt_count`, enqueue
    immediately (via `Acquisition.force_search_now/1`).
  - `:abandoned` / `:cancelled` grab → delegate to `Acquisition.rearm_grab/1`
    (resets `attempt_count` to 0).
  - `:grabbed` grab → restart it via `Acquisition.restart_grabbed_grab/1`.
    Used when the file never landed at the download client (the pursuit
    is "Waiting / Not visible in your download client") — the prior
    grab is treated as failed and a fresh search begins.
  - any other grab state → `{:error, :not_eligible}`.
  """

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Runner
  alias MediaCentarr.Acquisition.Pursuits.Events.PursuitReSearched

  @spec execute(%{pursuit_id: Ecto.UUID.t()}) ::
          {:ok, Pursuit.t()} | {:error, :not_found | :not_eligible | term()}
  def execute(%{pursuit_id: id}) when is_binary(id) do
    case Pursuits.get(id) do
      {:error, :not_found} = error ->
        error

      {:ok, %Pursuit{state: state}} when state != "active" ->
        {:error, :not_eligible}

      {:ok, %Pursuit{}} ->
        case Pursuits.latest_grab(id) do
          {:error, :not_found} -> {:error, :not_eligible}
          {:ok, grab} -> run_for(id, grab)
        end
    end
  end

  defp run_for(pursuit_id, %Grab{status: "snoozed"} = grab) do
    Runner.run(pursuit_id, "pursuit re-searched", fn pursuit ->
      with {:ok, _} <- Acquisition.force_search_now(grab.id),
           {:ok, _event} <-
             Events.record(%PursuitReSearched{
               pursuit_id: pursuit.id,
               pursuit_title: pursuit.title,
               occurred_at: DateTime.utc_now(:second)
             }) do
        {:ok, pursuit}
      end
    end)
  end

  defp run_for(pursuit_id, %Grab{status: status} = grab) when status in ~w(abandoned cancelled) do
    Runner.run(pursuit_id, "pursuit re-searched", fn pursuit ->
      with {:ok, _} <- Acquisition.rearm_grab(grab.id),
           {:ok, _event} <-
             Events.record(%PursuitReSearched{
               pursuit_id: pursuit.id,
               pursuit_title: pursuit.title,
               occurred_at: DateTime.utc_now(:second)
             }) do
        {:ok, pursuit}
      end
    end)
  end

  defp run_for(pursuit_id, %Grab{status: "grabbed"} = grab) do
    Runner.run(pursuit_id, "pursuit re-searched", fn pursuit ->
      with {:ok, _} <- Acquisition.restart_grabbed_grab(grab.id),
           {:ok, _event} <-
             Events.record(%PursuitReSearched{
               pursuit_id: pursuit.id,
               pursuit_title: pursuit.title,
               occurred_at: DateTime.utc_now(:second)
             }) do
        {:ok, pursuit}
      end
    end)
  end

  defp run_for(_pursuit_id, %Grab{}), do: {:error, :not_eligible}
end
