defmodule MediaCentaur.TMDB.Supervisor do
  @moduledoc """
  The TMDB adapter's processes: `RateLimiter` and `MetadataStats`.
  Independent, `:one_for_one`.
  """
  use Supervisor

  alias MediaCentaur.TMDB

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [TMDB.RateLimiter, TMDB.MetadataStats]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 30)
  end
end
