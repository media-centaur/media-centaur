defmodule MediaCentaur.Retention.SweepJob do
  @moduledoc """
  Daily execution of every `:sweep`-mode retention policy via
  `MediaCentaur.Retention.sweep/0`.

  Scheduled by `Oban.Plugins.Cron` (see `config/config.exs`). A policy
  that raises fails the job *after* the remaining policies have run, so
  Oban's retry re-attempts only what's needed — prune runs are
  idempotent.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias MediaCentaur.Retention

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Retention.sweep() do
      :ok ->
        :ok

      {:error, failures} ->
        keys = Enum.map_join(failures, ", ", fn {key, _exception} -> to_string(key) end)
        {:error, "retention sweep failed for: #{keys}"}
    end
  end
end
