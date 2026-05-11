defmodule MediaCentarr.Acquisition.Pursuits.Commands.AutoCancel do
  @moduledoc "Cancels the active target on a confirmed safe-case."

  import Ecto.Query

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Runner
  alias MediaCentarr.Acquisition.Pursuits.Events.AutoCancelled
  alias MediaCentarr.Acquisition.{Target, TargetStatus}
  alias MediaCentarr.Repo

  @doc """
  Cancels the in-flight target (if any) for the given pursuit and
  records the `auto_cancelled` event. Pursuit state is unchanged —
  the system has done what it could automatically; user-driven
  fallback or terminal close happens via separate commands.
  """
  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, reason: reason}) when is_atom(reason) do
    label = fn pursuit -> "pursuit auto-cancelled (#{reason}) — #{pursuit.title}" end

    Runner.run(id, label, fn pursuit ->
      cancel_active_target(pursuit, reason)

      with {:ok, _event} <-
             Events.record(%AutoCancelled{
               pursuit_id: pursuit.id,
               pursuit_title: pursuit.title,
               occurred_at: DateTime.utc_now(:second),
               reason: Atom.to_string(reason)
             }) do
        {:ok, pursuit}
      end
    end)
  end

  defp cancel_active_target(pursuit, reason) do
    Target
    |> where([t], t.pursuit_id == ^pursuit.id and t.status in ^TargetStatus.in_flight())
    |> Repo.all()
    |> Enum.each(fn target ->
      Repo.update!(Target.cancelled_changeset(target, Atom.to_string(reason)))
    end)
  end
end
