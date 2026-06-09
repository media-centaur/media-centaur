defmodule MediaCentaur.TMDB.MetadataStatsTest do
  # async: false — the [:media_centaur, :metadata, :enriched] event is global, so
  # a per-instance handler still *catches* emits from any concurrent async test
  # (e.g. FetchMetadataTest), which would pollute total/recent. Running sync keeps
  # these tests from overlapping other emitters; within the file they're serial.
  use ExUnit.Case, async: false

  alias MediaCentaur.TMDB.MetadataStats

  setup do
    name = :"metadata_stats_#{:erlang.unique_integer([:positive])}"
    start_supervised!({MetadataStats, name: name})
    %{server: name}
  end

  defp enrich(server, attrs) do
    metadata = Map.merge(%{kind: :movie, title: "Sample Movie", year: 2024}, attrs)

    :telemetry.execute(
      [:media_centaur, :metadata, :enriched],
      %{system_time: System.system_time()},
      metadata
    )

    # snapshot/1 is a GenServer.call; the handler ran synchronously in this
    # process and cast to `server` before this read enqueues, so FIFO ordering
    # makes the record visible without sleeping.
    MetadataStats.snapshot(server)
  end

  describe "snapshot/1" do
    test "starts empty", %{server: server} do
      assert MetadataStats.snapshot(server) == MetadataStats.empty_snapshot()
    end

    test "records a successful enrichment", %{server: server} do
      snapshot = enrich(server, %{kind: :tv_series, title: "Sample Show", year: 2022})

      assert snapshot.total == 1
      assert %DateTime{} = snapshot.last_enriched_at
      assert [%{kind: :tv_series, title: "Sample Show", year: 2022, at: %DateTime{}}] = snapshot.recent
    end

    test "keeps the recent feed newest-first and bounded", %{server: server} do
      for n <- 1..12, do: enrich(server, %{title: "Title #{n}"})
      snapshot = MetadataStats.snapshot(server)

      assert snapshot.total == 12
      assert length(snapshot.recent) == 8
      assert hd(snapshot.recent).title == "Title 12"
    end
  end

  describe "resilience" do
    test "snapshot/1 returns the empty snapshot when the server is down" do
      assert MetadataStats.snapshot(:metadata_stats_not_started) == MetadataStats.empty_snapshot()
    end
  end
end
