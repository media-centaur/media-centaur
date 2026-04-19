defmodule MediaCentarr.SelfUpdate.CheckerJob do
  @moduledoc """
  Oban worker that polls the GitHub Releases API for the latest Media
  Centarr tag and persists the result.

  Runs on a 6-hour cron and is also enqueued on app boot when the
  persisted `last_check_at` is stale. Deduplicated within a 1-hour
  window so rapid restarts and cron firings don't pile up duplicate
  jobs.

  The job broadcasts `{:check_complete, outcome}` on the
  `self_update:status` topic so LiveViews can react without polling.
  """

  use Oban.Worker,
    queue: :self_update,
    unique: [period: 3600]

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.SelfUpdate.{Storage, UpdateChecker}
  alias MediaCentarr.Topics

  @impl Oban.Worker
  def perform(_job) do
    if MediaCentarr.SelfUpdate.enabled?() do
      broadcast({:check_started})
      outcome = run_check()
      broadcast({:check_complete, outcome})
    end

    :ok
  end

  @doc """
  Enqueues an immediate check, bypassing the 1-hour unique window by
  using `replace: [:scheduled]` so a manual "Check now" always wins.
  """
  @spec enqueue_now() :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_now do
    Oban.insert(new(%{}, replace: [scheduled: [:scheduled_at, :args]]))
  end

  @doc """
  Enqueues a check to run after `delay_seconds`, subject to the worker's
  uniqueness constraint. Used at app boot when the persisted check is
  stale.
  """
  @spec enqueue_after(pos_integer()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_after(delay_seconds) when delay_seconds > 0 do
    Oban.insert(new(%{}, schedule_in: delay_seconds))
  end

  defp run_check do
    case Storage.record_check_result(UpdateChecker.latest_release()) do
      {:ok, classification, release} ->
        {classification, release}

      {:error, reason} = error ->
        Log.warning(:system, "update check failed: #{inspect(reason)}")
        error
    end
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.self_update_status(),
      message
    )
  end
end
