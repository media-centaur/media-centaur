defmodule MediaCentaur.SelfUpdate.CheckerJob do
  @moduledoc """
  Oban worker that polls the GitHub Releases API for the latest Media
  Centaur tag and persists the result.

  Runs on a 15-minute cron (the rate-limit floor) and is also enqueued
  on app boot when the persisted `last_check_at` is stale. The
  user-facing interval is honoured by the `due_for_check?/5` gate, not
  the cron — so the `unique` window only guards against a boot enqueue
  racing a cron tick, and must stay *below* the cron interval or it
  would silently cap the user's setting to its own period.

  The job broadcasts `{:check_complete, outcome, :scheduled}` on the
  `self_update:status` topic so LiveViews can react without polling. The
  `:scheduled` source is what lets AutoApply auto-install from this path (a
  manual check passes `:manual` and is never auto-applied).
  """

  use Oban.Worker,
    queue: :self_update,
    # Must stay below the 15-minute cron interval. A longer window (this
    # was 3600s) deduplicates legitimate scheduled ticks and caps the
    # user's check interval to its own period — the bug that made a
    # 15-minute setting behave as roughly hourly. 2 minutes only guards a
    # boot enqueue racing a cron tick; the real interval lives in the gate.
    unique: [period: 120]

  alias MediaCentaur.Config
  alias MediaCentaur.SelfUpdate
  alias MediaCentaur.SelfUpdate.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    forced? = Map.get(args, "force", false) == true

    if SelfUpdate.enabled?() and check_due?(forced?) do
      # The check itself (fetch + record + broadcast) lives in the context, so
      # the scheduled path and the LiveView's manual check share one impl. This
      # is the unattended poll — `:scheduled` is the only source AutoApply will
      # auto-install on.
      SelfUpdate.run_check(:scheduled)
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
  Enqueues an immediate, **forced** check, bypassing the unique window via
  `replace: [scheduled: [:scheduled_at, :args]]` so a manual "Check now"
  always wins. `force`
  also bypasses the `due_for_check?/5` interval gate — a manual check must
  contact GitHub even if a scheduled check ran moments ago — and routes
  through the broadcasting job path so AutoApply and any open LiveView
  react to the result uniformly.
  """
  @spec enqueue_now() :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_now do
    Oban.insert(new(%{"force" => true}, replace: [scheduled: [:scheduled_at, :args]]))
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
end
