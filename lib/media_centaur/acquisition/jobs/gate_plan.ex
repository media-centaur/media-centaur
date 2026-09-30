defmodule MediaCentaur.Acquisition.Jobs.GatePlan do
  @moduledoc """
  Runs the approval gate (`Plans.Gate`) for a plan that has just turned
  `ready`. `Jobs.RunPlan` inserts it in the same transaction as the
  transition, only for a gated plan (`Plans.Gate.needed?/1`), so a gated
  plan is never ready without its gate owed (ADR-077, rule 1).

  The plan is re-read when the job runs: one discarded or committed
  meanwhile is left alone.
  """

  # Unique among gates that have not started (ADR-077, rule 6): a gate
  # that ran for an earlier `ready` never absorbs the next one.
  use Oban.Worker,
    queue: :acquisition,
    unique: [period: :infinity, keys: [:plan_id], states: [:available, :scheduled, :retryable]]

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Plans.Gate

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"plan_id" => plan_id}}) do
    case Plans.fetch(plan_id) do
      {:ok, plan} -> Gate.run(plan)
      {:error, :not_found} -> :ok
    end
  end
end
