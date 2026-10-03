# POLICY: append-only (ADR-027). Each row is a crossing the extractor must always
# report — the recall floor. A refinement that loses one is rejected.
defmodule MediaCentaur.ContextMap.FixtureInstancesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap
  alias MediaCentaur.ContextMap.Finding

  setup_all do
    analysis = ContextMap.analyse()
    %{findings: analysis.findings, document: ContextMap.document(analysis, %{})}
  end

  @ignored_consumers [
    MediaCentaurWeb.Components.Title.Logic,
    MediaCentaurWeb.Components.Title.WatchlistToggle,
    MediaCentaurWeb.Components.Title.TrackingControls,
    MediaCentaurWeb.SocialLive.FeedEntries
  ]

  for consumer <- @ignored_consumers do
    test "R3: TitleIntent.rung :ignored interpreted in #{inspect(consumer)}", %{findings: findings} do
      assert Enum.any?(
               findings,
               &match?(
                 %Finding{
                   rule: "R3",
                   schema: MediaCentaur.Watchlist.TitleIntent,
                   field: :rung,
                   value: :ignored,
                   consumer: unquote(consumer)
                 },
                 &1
               )
             )
    end
  end

  test "R3: the Incoming search surface carries the ignored marker", %{findings: findings} do
    logic =
      Enum.find(
        findings,
        &match?(
          %Finding{rule: "R3", value: :ignored, consumer: MediaCentaurWeb.Components.Title.Logic},
          &1
        )
      )

    assert MediaCentaurWeb.IncomingLive in logic.surfaces
  end

  test "R1: TitleIntent.activity_id is never read by Watchlist", %{findings: findings} do
    assert Enum.any?(
             findings,
             &match?(
               %Finding{
                 rule: "R1",
                 schema: MediaCentaur.Watchlist.TitleIntent,
                 field: :activity_id,
                 detail: %{kind: :owner_never_reads}
               },
               &1
             )
           )
  end

  test "R1: TitleIntent.source is never read by Watchlist", %{findings: findings} do
    assert Enum.any?(
             findings,
             &match?(
               %Finding{
                 rule: "R1",
                 schema: MediaCentaur.Watchlist.TitleIntent,
                 field: :source,
                 detail: %{kind: :owner_never_reads}
               },
               &1
             )
           )
  end

  test "R4: TitleIntent.activity_id keys into Activities, which Watchlist does not depend on",
       %{findings: findings} do
    assert Enum.any?(
             findings,
             &match?(
               %Finding{
                 rule: "R4",
                 schema: MediaCentaur.Watchlist.TitleIntent,
                 field: :activity_id,
                 detail: %{target: MediaCentaur.Activities.Activity, in_deps: false}
               },
               &1
             )
           )
  end

  test "R2: ReleaseTracking.Item.library_container_id resolves through its type column into the kernel",
       %{document: document} do
    assert Enum.any?(
             document.kernel_reads,
             &(&1.schema == "MediaCentaur.ReleaseTracking.Item" and
                 &1.field == "library_container_id" and
                 &1.target == "MediaCentaur.Library.Movie")
           )
  end

  test "R2: WatchHistory.Event.movie_id is a kernel read into Library.Movie", %{document: document} do
    assert Enum.any?(
             document.kernel_reads,
             &(&1.schema == "MediaCentaur.WatchHistory.Event" and &1.field == "movie_id" and
                 &1.target == "MediaCentaur.Library.Movie")
           )
  end
end
