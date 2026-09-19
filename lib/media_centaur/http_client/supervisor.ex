defmodule MediaCentaur.HttpClient.Supervisor do
  @moduledoc """
  Supervises the HTTP layer's stateful pieces: the response-cache
  coordinator, the request time-series store and `Traffic`, which feeds
  it.

  Started before any context that builds clients, in dev and prod only;
  under `:test` the seam runs uncached and unrecorded so `Req.Test`
  stubs never share state across tests, and `Traffic`'s reads return
  empty values.

  `snapshot_dir:` is where the store keeps `traffic.snapshot`; the
  application passes the database's directory (ADR-070).
  """
  use Supervisor

  alias MediaCentaur.HttpClient.Traffic
  alias MediaCentaur.TimeSeries.Store

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    snapshot_path =
      case Keyword.get(opts, :snapshot_dir) do
        nil -> nil
        dir -> Path.join(dir, "traffic.snapshot")
      end

    children = [
      MediaCentaur.HttpClient.Cache.Coordinator,
      {Store,
       name: Traffic.Store,
       table: Traffic.store_table(),
       schema: Traffic.schema(),
       snapshot_path: snapshot_path,
       retention_policy: :request_history},
      Traffic
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
