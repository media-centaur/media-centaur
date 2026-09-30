defmodule MediaCentaur.Review.SettleJob do
  @moduledoc """
  The periodic pass that carries out approvals whose import was lost
  (`Review.settle_with_library/1`, campaign durable-work F1). Cron, every
  five minutes; an approval younger than fifteen minutes may still be
  importing and is left for the next pass.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias MediaCentaur.Review

  @in_flight_minutes 15

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.add(DateTime.utc_now(), -@in_flight_minutes * 60, :second)
    Review.settle_with_library(approved_before: cutoff)
    :ok
  end
end
