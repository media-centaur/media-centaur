defmodule MediaCentaur.TMDB.ReferencesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TMDB.References

  defmodule Tracked do
    @behaviour References.Provider
    def references, do: MapSet.new([{1, :movie}, {2, :tv_series}])
    def schedules_checks?, do: true
  end

  defmodule Friends do
    @behaviour References.Provider
    def references, do: MapSet.new([{2, :tv_series}, {3, :movie}])
    def schedules_checks?, do: false
  end

  test "all/1 is the union of every provider's references" do
    assert References.all([Tracked, Friends]) ==
             MapSet.new([{1, :movie}, {2, :tv_series}, {3, :movie}])
  end

  test "scheduled/1 is the union of the providers that schedule checks" do
    assert References.scheduled([Tracked, Friends]) == MapSet.new([{1, :movie}, {2, :tv_series}])
  end

  test "the configured providers are the four contexts that hold titles" do
    assert References.providers() == [
             MediaCentaur.ReleaseTracking.TmdbReferences,
             MediaCentaur.Acquisition.TmdbReferences,
             MediaCentaur.Discovery.TmdbReferences,
             MediaCentaur.Activities.TmdbReferences
           ]
  end
end
