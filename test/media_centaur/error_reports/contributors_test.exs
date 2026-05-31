defmodule MediaCentaur.ErrorReports.ContributorsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.ErrorReports.Contributors

  # Stub implementations of the IncidentContext behaviour. The registry is
  # injected per-call, so these tests never touch Application config.
  defmodule FullContributor do
    @behaviour MediaCentaur.ErrorReports.IncidentContext
    @impl true
    def assess, do: {:fault, :stalled, :error, %{queue: 1}}
    @impl true
    def gather(ids), do: %{seen: ids, from: :full}
  end

  defmodule GatherOnly do
    @behaviour MediaCentaur.ErrorReports.IncidentContext
    @impl true
    def gather(_ids), do: %{from: :gather_only}
  end

  defmodule AssessOnly do
    @behaviour MediaCentaur.ErrorReports.IncidentContext
    @impl true
    def assess, do: :ok
  end

  defmodule Crasher do
    @behaviour MediaCentaur.ErrorReports.IncidentContext
    @impl true
    def gather(_ids), do: raise("contributor blew up")
  end

  defmodule BadReturn do
    @behaviour MediaCentaur.ErrorReports.IncidentContext
    @impl true
    def gather(_ids), do: :not_a_map
  end

  @registry %{
    pipeline: FullContributor,
    tmdb: GatherOnly,
    watcher: AssessOnly,
    broken: Crasher,
    weird: BadReturn
  }

  describe "module_for/2" do
    test "resolves a registered component" do
      assert Contributors.module_for(:pipeline, @registry) == FullContributor
    end

    test "returns nil for an unregistered component" do
      assert Contributors.module_for(:unknown, @registry) == nil
    end
  end

  describe "gather/3" do
    test "returns the contributor's context map" do
      assert Contributors.gather(:tmdb, %{tmdb_id: 7}, @registry) == %{from: :gather_only}

      assert Contributors.gather(:pipeline, %{file: "x"}, @registry) == %{
               seen: %{file: "x"},
               from: :full
             }
    end

    test "degrades to %{} for an unregistered component" do
      assert Contributors.gather(:unknown, %{}, @registry) == %{}
    end

    test "degrades to %{} when the module does not implement gather/1" do
      assert Contributors.gather(:watcher, %{}, @registry) == %{}
    end

    test "degrades to %{} when the contributor crashes" do
      assert Contributors.gather(:broken, %{}, @registry) == %{}
    end

    test "degrades to %{} when the contributor returns a non-map" do
      assert Contributors.gather(:weird, %{}, @registry) == %{}
    end
  end

  describe "assessors/1" do
    test "lists only components whose module implements assess/0" do
      assessors = Enum.sort(Contributors.assessors(@registry))

      assert assessors == Enum.sort([{:pipeline, FullContributor}, {:watcher, AssessOnly}])
    end

    test "is empty for an empty registry" do
      assert Contributors.assessors(%{}) == []
    end
  end

  describe "registry/0" do
    test "reads the configured contributor map" do
      # config.exs registers TMDB as the first contributor.
      assert Contributors.registry()[:tmdb] == MediaCentaur.TMDB.IncidentContext
    end
  end
end
