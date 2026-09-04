defmodule MediaCentaur.HttpClient.IncidentContextTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.HttpClient.{IncidentContext, Stats}

  defp snapshot_with(overrides) do
    snapshot = Stats.empty_snapshot()

    upstreams =
      Enum.map(snapshot.upstreams, fn row ->
        case Map.fetch(overrides, row.id) do
          {:ok, {requests, errors}} ->
            %{row | window: %{row.window | requests: requests, errors: errors}}

          :error ->
            row
        end
      end)

    %{snapshot | upstreams: upstreams}
  end

  test "healthy traffic is :ok" do
    assert IncidentContext.assess(snapshot_with(%{tmdb: {40, 2}})) == :ok
  end

  test "a mostly-failing upstream is a warning fault titled after it" do
    assert {:fault, :upstream_failing, :warning, %{upstream: :tmdb, headline: headline}} =
             IncidentContext.assess(snapshot_with(%{tmdb: {20, 15}}))

    assert headline == "Most requests to TMDB are failing"
  end

  test "too few requests never fault, whatever their outcome" do
    assert IncidentContext.assess(snapshot_with(%{tmdb: {5, 5}})) == :ok
  end

  test "upstreams another subsystem assesses are left to it" do
    assert IncidentContext.assess(snapshot_with(%{prowlarr: {30, 30}, github: {30, 30}})) == :ok
  end

  test "the worst upstream wins when several fail" do
    assert {:fault, _kind, _severity, %{upstream: :steam}} =
             IncidentContext.assess(snapshot_with(%{tmdb: {20, 11}, steam: {20, 20}}))
  end

  test "vitals carry every upstream and the cache size" do
    assert %{"upstreams" => upstreams, "cache_entries" => 0} = IncidentContext.vitals()
    assert %{"window_requests" => 0, "session_requests" => 0} = upstreams["tmdb"]
  end
end
