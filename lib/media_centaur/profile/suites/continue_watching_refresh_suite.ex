defmodule MediaCentaur.Profile.Suites.ContinueWatchingRefreshSuite do
  @moduledoc """
  Standalone refresh-cost measurement, isolated from the read-path
  suite so cold-fallback reads stay honest. Always operates on a
  warm cache (refresh_cache itself ensures the table exists).
  """
  @behaviour MediaCentaur.Profile.Suite

  alias MediaCentaur.Library.Views.ContinueWatching

  @impl true
  def name, do: "Library.Views.ContinueWatching.refresh_cache/0"

  @impl true
  def inputs, do: %{}

  @impl true
  def scenarios do
    %{
      "ContinueWatching.refresh_cache/0" => fn -> ContinueWatching.refresh_cache() end
    }
  end
end
