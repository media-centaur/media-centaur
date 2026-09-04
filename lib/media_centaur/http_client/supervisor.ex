defmodule MediaCentaur.HttpClient.Supervisor do
  @moduledoc """
  Supervises the HTTP layer's two stateful pieces: the response-cache
  coordinator and the per-upstream request stats.

  Started before any context that builds clients, in dev and prod only;
  under `:test` the seam runs uncached and unrecorded so `Req.Test`
  stubs never share state across tests.
  """
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      MediaCentaur.HttpClient.Cache.Coordinator,
      MediaCentaur.HttpClient.Stats
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
