defmodule MediaCentaur.Pipeline.RetentionPolicies do
  @moduledoc """
  Retention policies owned by the Pipeline: the image download queue
  keeps finished rows only briefly, and drops rows of any status that
  nothing has touched for a month — the retry scheduler bumps live rows,
  so an untouched row belongs to a deleted entity or a dead download.
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.Pipeline.ImageQueue
  alias MediaCentaur.Retention.Policy

  @completed_retention_days 7
  @stale_retention_days 30

  @impl true
  def policies do
    [
      %Policy{
        key: :image_queue,
        subsystem: :pipeline,
        label: "Image download queue",
        description:
          "Bookkeeping for finished artwork downloads is cleared after " <>
            "#{@completed_retention_days} days; queue entries untouched for " <>
            "#{@stale_retention_days} days are dropped. The artwork files themselves are kept.",
        mode: :sweep,
        run: fn ->
          now = DateTime.utc_now()

          ImageQueue.prune(
            DateTime.add(now, -@completed_retention_days, :day),
            DateTime.add(now, -@stale_retention_days, :day)
          )
        end
      }
    ]
  end
end
