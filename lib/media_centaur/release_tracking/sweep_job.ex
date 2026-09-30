defmodule MediaCentaur.ReleaseTracking.SweepJob do
  @moduledoc """
  The want-ledger sweep, every quarter hour: items whose library container
  is gone are detached (`ReleaseTracking.detach_dangling_containers/0`),
  `ReleaseTracking.sync_wants/1` runs for every tracked item, then `{:tracking_sweep_completed}` on
  `Topics.release_tracking_updates/0` — the drop planner's clock
  (`Acquisition.Reactor`). No TMDB request: a release becomes wanted
  because its air date passed, a fact about the calendar the app already
  holds. Took over the refresher's second timer when the refresher was
  retired (ADR-071).
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing]]

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Topics

  @impl Oban.Worker
  def perform(_job) do
    # An item whose library container was deleted while the
    # `containers_deleted` message was lost is detached here first.
    ReleaseTracking.detach_dangling_containers()
    Enum.each(ReleaseTracking.list_all_items(), &ReleaseTracking.sync_wants/1)
    Topics.publish(Topics.release_tracking_updates(), {:tracking_sweep_completed})
    :ok
  end
end
