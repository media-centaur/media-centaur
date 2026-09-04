defmodule MediaCentaur.Profile.Suites.WatchHistorySummaryRefreshSuite do
  @moduledoc """
  Standalone refresh-cost measurement for the WatchHistory summary
  projection, isolated from the read-path suite.
  """
  @behaviour MediaCentaur.Profile.Suite

  alias MediaCentaur.WatchHistory.Views.Summary

  @impl true
  def name, do: "WatchHistory.Views.Summary.refresh_cache/0"

  @impl true
  def inputs, do: %{}

  @impl true
  def scenarios do
    %{
      "Summary.refresh_cache/0" => fn -> Summary.refresh_cache() end
    }
  end
end
