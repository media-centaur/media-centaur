defmodule MediaCentaur.HttpClient.IncidentContextTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.HttpClient.{IncidentContext, Stats}
  alias MediaCentaur.IntegrationAvailability.Status

  @now ~U[2026-09-18 12:00:00Z]

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

  defp up, do: %Status{integration: :tmdb, state: :up, observed_at: @now}

  defp down(reason, minutes_ago) do
    %Status{
      integration: :tmdb,
      state: {:down, DateTime.add(@now, -minutes_ago * 60, :second), reason},
      observed_at: @now
    }
  end

  defp assess(snapshot, tmdb_status \\ nil),
    do: IncidentContext.assess(snapshot, tmdb_status || up(), @now)

  test "healthy traffic is :ok" do
    assert assess(snapshot_with(%{tmdb: {40, 2}})) == :ok
  end

  describe "TMDB — graded by availability, not by how much traffic happens to fail" do
    # Held work makes no requests, so request share says nothing about a
    # down TMDB: during an outage the only traffic is the probe, three
    # requests per fifteen minutes, below any share floor. The value a
    # probe keeps current is the evidence instead.
    test "an outage past the grace window faults, with no traffic at all" do
      assert {:fault, :upstream_unavailable, :warning, %{upstream: :tmdb, headline: headline}} =
               assess(Stats.empty_snapshot(), down(:unreachable, 10))

      assert headline == "TMDB is unreachable"
    end

    test "each reason says what to go and fix" do
      assert {:fault, _kind, _sev, %{headline: "TMDB rejected the API key"}} =
               assess(Stats.empty_snapshot(), down(:rejected, 10))

      assert {:fault, _kind, _sev, %{headline: "TMDB is rate-limiting requests"}} =
               assess(Stats.empty_snapshot(), down(:rate_limited, 10))
    end

    test "an outage younger than the grace window stays quiet — a probe has not confirmed it" do
      assert assess(Stats.empty_snapshot(), down(:unreachable, 2)) == :ok
    end

    test "a TMDB that answers never faults on request share — a 404 is not an outage" do
      assert assess(snapshot_with(%{tmdb: {20, 15}})) == :ok
    end
  end

  describe "the image CDN — still graded by request share" do
    # The CDN writes no availability value of its own (different host
    # from the API), so failing traffic is all the evidence there is.
    test "a mostly-failing CDN is a warning fault titled after it" do
      assert {:fault, :upstream_failing, :warning, %{upstream: :tmdb_images, headline: headline}} =
               assess(snapshot_with(%{tmdb_images: {20, 15}}))

      assert headline == "Most requests to TMDB images are failing"
    end

    test "too few requests never fault, whatever their outcome" do
      assert assess(snapshot_with(%{tmdb_images: {5, 5}})) == :ok
    end
  end

  test "upstreams another subsystem assesses, and Steam, are left alone" do
    assert assess(snapshot_with(%{prowlarr: {30, 30}, github: {30, 30}, steam: {30, 30}})) == :ok
  end

  test "a down TMDB outranks a failing CDN — it is the one with a remedy" do
    assert {:fault, :upstream_unavailable, _severity, %{upstream: :tmdb}} =
             assess(snapshot_with(%{tmdb_images: {20, 20}}), down(:unreachable, 10))
  end

  test "vitals carry every upstream and the cache size" do
    assert %{"upstreams" => upstreams, "cache_entries" => 0} = IncidentContext.vitals()
    assert %{"window_requests" => 0, "session_requests" => 0} = upstreams["tmdb"]
  end
end
