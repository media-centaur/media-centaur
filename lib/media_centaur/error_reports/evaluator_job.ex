defmodule MediaCentaur.ErrorReports.EvaluatorJob do
  @moduledoc """
  Oban cron job that drives `ErrorReports.Evaluator.run/1` on a schedule, polling
  every registered subsystem's `assess/0` and reconciling `:subsystem` incidents.

  Scheduled in `config/config.exs` on the `maintenance` queue alongside the
  retention prune. Stateless between runs — the open-incident set in the store
  is the only state it reads.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias MediaCentaur.ErrorReports.Evaluator

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Evaluator.run()
    :ok
  end
end
