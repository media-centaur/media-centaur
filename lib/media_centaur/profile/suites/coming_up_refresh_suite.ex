defmodule MediaCentaur.Profile.Suites.ComingUpRefreshSuite do
  @moduledoc """
  Standalone refresh-cost measurement, isolated from the read-path
  suite so cold-fallback reads stay honest.
  """
  @behaviour MediaCentaur.Profile.Suite

  alias MediaCentaur.ReleaseTracking.Views.ComingUp

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
