defmodule MediaCentarr.Profile.Suites.HeroCandidatesSuite do
  @moduledoc """
  Validates the projection vs. legacy DB query for Hero Candidates
  (ADR-041). Compares cached and uncached read paths.

  Two inputs:

    * `warm-cache` — `HeroCandidates.refresh_cache/0` is called first,
      so `Views.hero_candidates/1` reads from
      `:library_view_hero_candidates` (ETS).
    * `cold-fallback` — the ETS table is wiped, so
      `Views.hero_candidates/1` falls through to
      `Library.list_hero_candidates/1` (DB). Both functions are timed
      under both inputs so the comparison is symmetric.
  """
  @behaviour MediaCentarr.Profile.Suite

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Views
  alias MediaCentarr.Library.Views.HeroCandidates

  @table :library_view_hero_candidates

  @impl true
  def name, do: "Library.Views.HeroCandidates"

  @impl true
  def inputs do
    %{
      "warm-cache" => fn -> HeroCandidates.refresh_cache() end,
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
    %{
      "Views.hero_candidates/1 (limit: 12)" => fn ->
        Views.hero_candidates(limit: 12)
      end,
      "Library.list_hero_candidates/1 (limit: 12)" => fn ->
        Library.list_hero_candidates(limit: 12)
      end
    }
  end
end

defmodule MediaCentarr.Profile.Suites.HeroCandidatesRefreshSuite do
  @moduledoc """
  Standalone refresh-cost measurement, isolated from the read-path
  suite so cold-fallback reads stay honest. Always operates on a
  warm cache (refresh_cache itself ensures the table exists).
  """
  @behaviour MediaCentarr.Profile.Suite

  alias MediaCentarr.Library.Views.HeroCandidates

  @impl true
  def name, do: "Library.Views.HeroCandidates.refresh_cache/0"

  @impl true
  def inputs, do: %{}

  @impl true
  def scenarios do
    %{
      "HeroCandidates.refresh_cache/0" => fn -> HeroCandidates.refresh_cache() end
    }
  end
end
