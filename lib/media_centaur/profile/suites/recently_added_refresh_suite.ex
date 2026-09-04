defmodule MediaCentaur.Profile.Suites.RecentlyAddedRefreshSuite do
  @moduledoc """
  Standalone refresh-cost measurement, isolated from the read-path
  suite so cold-fallback reads stay honest.
  """
  @behaviour MediaCentaur.Profile.Suite

  alias MediaCentaur.Library.Views.RecentlyAdded

  @impl true
  def name, do: "Library.Views.RecentlyAdded.refresh_cache/0"

  @impl true
  def inputs, do: %{}

  @impl true
  def scenarios do
    %{
      "RecentlyAdded.refresh_cache/0" => fn -> RecentlyAdded.refresh_cache() end
    }
  end
end
