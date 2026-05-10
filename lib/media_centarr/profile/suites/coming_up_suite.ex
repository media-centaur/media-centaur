defmodule MediaCentarr.Profile.Suites.ComingUpSuite do
  @moduledoc """
  Validates the projection vs. legacy DB query for Coming Up
  (ADR-041). Compares cached and uncached read paths.

  Two inputs:

    * `warm-cache` — `ComingUp.refresh_cache/0` is called first, so
      `Views.coming_up/3` reads from `:release_tracking_view_coming_up`
      (ETS).
    * `cold-fallback` — the ETS table is wiped, so `Views.coming_up/3`
      falls through to `ReleaseTracking.list_releases_between/3` (DB).
  """
  @behaviour MediaCentarr.Profile.Suite

  alias MediaCentarr.ReleaseTracking
  alias MediaCentarr.ReleaseTracking.Views
  alias MediaCentarr.ReleaseTracking.Views.ComingUp

  @table :release_tracking_view_coming_up

  @impl true
  def name, do: "ReleaseTracking.Views.ComingUp"

  @impl true
  def inputs do
    %{
      "warm-cache" => fn -> ComingUp.refresh_cache() end,
      "cold-fallback" => fn ->
        case :ets.whereis(@table) do
          :undefined -> :ok
          _ -> :ets.delete(@table)
        end
      end
    }
  end

  @impl true
  def scenarios do
    today = Date.utc_today()
    to_date = Date.add(today, 90)

    %{
      "Views.coming_up/3 (limit: 30)" => fn ->
        Views.coming_up(today, to_date, limit: 30)
      end,
      "ReleaseTracking.list_releases_between/3 (limit: 30)" => fn ->
        ReleaseTracking.list_releases_between(today, to_date, limit: 30)
      end
    }
  end
end

defmodule MediaCentarr.Profile.Suites.ComingUpRefreshSuite do
  @moduledoc """
  Standalone refresh-cost measurement, isolated from the read-path
  suite so cold-fallback reads stay honest.
  """
  @behaviour MediaCentarr.Profile.Suite

  alias MediaCentarr.ReleaseTracking.Views.ComingUp

  @impl true
  def name, do: "ReleaseTracking.Views.ComingUp.refresh_cache/0"

  @impl true
  def inputs, do: %{}

  @impl true
  def scenarios do
    %{
      "ComingUp.refresh_cache/0" => fn -> ComingUp.refresh_cache() end
    }
  end
end
