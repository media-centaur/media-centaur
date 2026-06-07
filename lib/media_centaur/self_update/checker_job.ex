defmodule MediaCentaur.SelfUpdate.CheckerJob do
  @moduledoc """
  Oban worker that polls the GitHub Releases API for the latest Media
  Centaur tag and persists the result.

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

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Config
  alias MediaCentaur.SelfUpdate.{Storage, UpdateChecker}
  alias MediaCentaur.Topics

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    forced? = Map.get(args, "force", false) == true

    if MediaCentaur.SelfUpdate.enabled?() and check_due?(forced?) do
      broadcast({:check_started})
      outcome = run_check()
      broadcast({:check_complete, outcome})
    end

    :ok
  end

  # The cron tick fires at the rate-limit floor; this gate decides whether
  # a given tick actually contacts GitHub, so the user-facing interval is a
  # pure Config read with no Oban reconfiguration. A forced (manual) check
  # always runs; otherwise we honour `update_check_enabled` and the elapsed
  # interval.
  defp check_due?(forced?) do
    last_check_at =
      case Storage.get_last_check_at() do
        {:ok, at} -> at
        :none -> nil
      end

    due_for_check?(
      forced?,
      Config.get(:update_check_enabled),
      Config.update_check_interval_minutes(),
      last_check_at,
      DateTime.utc_now()
    )
  end

  @doc """
  Pure decision: should this tick contact GitHub?

  `force?` (a manual "Check now") always wins. Otherwise checking must be
  enabled and at least `interval_minutes` must have elapsed since
  `last_check_at` (`nil` = never checked = due).
  """
  @spec due_for_check?(boolean(), boolean(), pos_integer(), DateTime.t() | nil, DateTime.t()) ::
          boolean()
  def due_for_check?(force?, enabled?, interval_minutes, last_check_at, now)
  def due_for_check?(true, _enabled?, _interval, _last, _now), do: true
  def due_for_check?(false, false, _interval, _last, _now), do: false
  def due_for_check?(false, true, _interval, nil, _now), do: true

  def due_for_check?(false, true, interval_minutes, %DateTime{} = last, %DateTime{} = now) do
    DateTime.diff(now, last, :minute) >= interval_minutes
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
      MediaCentaur.PubSub,
      Topics.self_update_status(),
      message
    )
  end
end
