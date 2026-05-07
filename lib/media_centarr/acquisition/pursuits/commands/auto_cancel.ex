defmodule MediaCentarr.Acquisition.Pursuits.Commands.AutoCancel do
  @moduledoc "Cancels the active grab on a confirmed safe-case."

  import Ecto.Query

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.GrabStatus
  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Events.AutoCancelled
  alias MediaCentarr.Repo

  @doc """
  Cancels the in-flight grab (if any) for the given pursuit and records the
  `auto_cancelled` event. Pursuit state is unchanged in v1 — the system has
  done what it could automatically; user-driven fallback or terminal close
  happens via separate commands.
  """
  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, reason: reason}) when is_atom(reason) do
    case Repo.get(Pursuit, id) do
      nil ->
        {:error, :not_found}

      %Pursuit{} = pursuit ->
        tap(
          Repo.transaction(fn ->
            cancel_active_grab(pursuit, reason)

            case record_event(pursuit, reason) do
              {:ok, _event} -> pursuit
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end),
          fn
            {:ok, %Pursuit{title: t}} ->
              Log.info(:acquisition, "pursuit auto-cancelled (#{reason}) — #{t}")

            _ ->
              :ok
          end
        )
    end
  end

  defp cancel_active_grab(pursuit, reason) do
    Grab
    |> where([g], g.pursuit_id == ^pursuit.id and g.status in ^GrabStatus.in_flight())
    |> Repo.all()
    |> Enum.each(fn grab ->
      Repo.update!(Grab.cancelled_changeset(grab, Atom.to_string(reason)))
    end)
  end

  defp record_event(pursuit, reason) do
    Events.record(%AutoCancelled{
      pursuit_id: pursuit.id,
      pursuit_title: pursuit.title,
      occurred_at: DateTime.utc_now(:second),
      reason: Atom.to_string(reason)
    })
  end
end
