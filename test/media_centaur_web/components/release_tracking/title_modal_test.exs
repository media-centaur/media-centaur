defmodule MediaCentaurWeb.Components.ReleaseTracking.TitleModalTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaurWeb.Components.ReleaseTracking.TitleModal

  @today ~D[2026-08-03]

  defp event(overrides) do
    struct!(
      %Event{
        id: "event-1",
        item_id: "item-1",
        item_name: "Sample Show",
        media_type: :tv_series,
        air_date: @today,
        status: :upcoming,
        kind: :episode
      },
      overrides
    )
  end

  describe "next_event/2" do
    test "picks the first event airing today or later" do
      past = event(%{id: "past", air_date: ~D[2026-07-28], status: :in_library})
      tonight = event(%{id: "tonight", air_date: @today})
      later = event(%{id: "later", air_date: ~D[2026-08-11]})

      assert %Event{id: "tonight"} = TitleModal.next_event([past, tonight, later], @today)
    end

    test "skips landed events even when dated in the future window" do
      landed = event(%{id: "landed", air_date: @today, status: :in_library})
      upcoming = event(%{id: "upcoming", air_date: ~D[2026-08-11]})

      assert %Event{id: "upcoming"} = TitleModal.next_event([landed, upcoming], @today)
    end

    test "returns nil when nothing is scheduled ahead" do
      past = event(%{id: "past", air_date: ~D[2026-07-01], status: :in_library})
      undated = event(%{id: "undated", air_date: nil, status: :unscheduled})

      assert TitleModal.next_event([past, undated], @today) == nil
      assert TitleModal.next_event([], @today) == nil
    end
  end
end
