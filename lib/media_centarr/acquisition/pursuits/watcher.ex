defmodule MediaCentarr.Acquisition.Pursuits.Watcher do
  @moduledoc """
  Periodic orchestrator driving Policy for every active pursuit.

  Dispatches Policy outputs to the corresponding command. Each Action
  variant maps to exactly one command:

      :no_action                       -> (skip)
      {:auto_cancel, reason}           -> Commands.AutoCancel
      {:request_decision, prompt}      -> Commands.RequestDecision
      {:satisfy, grab_id}              -> Commands.Satisfy
      {:exhaust, reason}               -> Commands.Exhaust

  Clauses for actions Policy v1 does not yet emit (`:auto_cancel`,
  `:request_decision`, `:satisfy`) are added as Policy gains them — kept
  out of the compiled artifact today so the project's zero-warning policy
  holds. The dispatch table grows additively; the Watcher never gains
  domain logic.
  """

  use Oban.Worker, queue: :acquisition

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.Commands.Exhaust
  alias MediaCentarr.Acquisition.Pursuits.{Policy, Snapshots}

  @impl Oban.Worker
  def perform(_job) do
    Enum.each(Pursuits.list_active(), fn pursuit ->
      pursuit
      |> Snapshots.build()
      |> Policy.evaluate()
      |> dispatch(pursuit)
    end)

    :ok
  end

  defp dispatch(:no_action, _pursuit), do: :ok

  defp dispatch({:exhaust, reason}, pursuit) do
    Log.info(:acquisition, "pursuit watcher dispatch — exhaust (#{reason}) — #{pursuit.title}")
    Exhaust.execute(%{pursuit_id: pursuit.id, reason: reason})
  end
end
