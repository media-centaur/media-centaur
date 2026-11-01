defmodule MediaCentaur.NewReleases.Kickoff do
  @moduledoc """
  The Discovery feature's runtime child (ADR-081, `Features.Runtime`): a
  one-shot task that enqueues one `RefreshJob` when the runtime starts, at
  boot or at turn-on, so the shelf fills then rather than at the next
  daily cron. The job is unique, so a kickoff beside a scheduled run adds
  nothing. Temporary: it runs once and is not restarted.
  """
  use Task, restart: :temporary

  alias MediaCentaur.NewReleases.RefreshJob

  @doc false
  def start_link(_arg), do: Task.start_link(&enqueue/0)

  @doc "Enqueues one refresh; a second call while one waits is a no-op."
  @spec enqueue() :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue, do: %{} |> RefreshJob.new() |> Oban.insert()
end
