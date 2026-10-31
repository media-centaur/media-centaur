defmodule MediaCentaur.Activities.StaleListingsJob do
  @moduledoc """
  Withdraws own listings whose title no longer stands at List
  (`Activities.withdraw_stale_listings/0`) — the repair for a withdrawal
  lost on its PubSub path (campaign durable-work, F8). Cron: at boot and
  hourly. Does nothing while the Social feature is off (ADR-081): cron is
  fixed at boot, so the job is where the flag is asked.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Activities
  alias MediaCentaur.Features

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Features.enabled?(:social) do
      case Activities.withdraw_stale_listings() do
        0 -> :ok
        count -> Log.info(:social, "withdrew #{count} listing(s) whose title left the watchlist")
      end
    end

    :ok
  end
end
