defmodule MediaCentaur.ReleaseTracking.DifferTest do
  use ExUnit.Case, async: true

  import MediaCentaur.TestFactory
  alias MediaCentaur.ReleaseTracking.Differ

  describe "diff/2" do
    test "detects no changes" do
      old = [
        build_tracking_release(%{
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2026-06-15],
          title: "Pilot"
        })
      ]

      new = [%{season_number: 1, episode_number: 1, air_date: ~D[2026-06-15], title: "Pilot"}]

      assert [] = Differ.diff(old, new)
    end

    test "detects date change" do
      old = [
        build_tracking_release(%{
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2026-06-15],
          title: "Pilot"
        })
      ]

      new = [%{season_number: 1, episode_number: 1, air_date: ~D[2026-07-01], title: "Pilot"}]

      assert [event] = Differ.diff(old, new)
      assert event.event_type == :upcoming_release_date_changed
      assert event.metadata.old_date == ~D[2026-06-15]
      assert event.metadata.new_date == ~D[2026-07-01]
    end

    test "detects new episodes" do
      old = [
        build_tracking_release(%{
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2026-06-15],
          title: "Pilot"
        })
      ]

      new = [
        %{season_number: 1, episode_number: 1, air_date: ~D[2026-06-15], title: "Pilot"},
        %{season_number: 1, episode_number: 2, air_date: ~D[2026-06-22], title: "Second"}
      ]

      assert [event] = Differ.diff(old, new)
      assert event.event_type == :new_episodes_announced
    end

    test "detects new season" do
      old = [
        build_tracking_release(%{
          season_number: 1,
          episode_number: 5,
          air_date: ~D[2026-06-15],
          title: "Finale"
        })
      ]

      new = [
        %{season_number: 1, episode_number: 5, air_date: ~D[2026-06-15], title: "Finale"},
        %{season_number: 2, episode_number: 1, air_date: ~D[2026-12-01], title: "Premiere"}
      ]

      events = Differ.diff(old, new)
      assert Enum.any?(events, &(&1.event_type == :new_season_announced))
    end

    test "detects removed releases" do
      old = [
        build_tracking_release(%{
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2026-06-15],
          title: "Pilot"
        }),
        build_tracking_release(%{
          season_number: 1,
          episode_number: 2,
          air_date: ~D[2026-06-22],
          title: "Second"
        })
      ]

      new = [%{season_number: 1, episode_number: 1, air_date: ~D[2026-06-15], title: "Pilot"}]

      assert [event] = Differ.diff(old, new)
      assert event.event_type == :removed_from_schedule
      assert String.contains?(event.description, "removed")
    end
  end

  describe "diff/3 — movies" do
    # Regression: a movie release has nil season/episode. The TV addition path
    # rolled nil into a "new season," minting a bogus "Season  announced" event
    # (the I Love Boosters bug). A movie has no season to announce.
    test "movie release addition produces no season announcement" do
      old = []

      new = [%{season_number: nil, episode_number: nil, air_date: ~D[2026-06-23], title: "Sample Film"}]

      events = Differ.diff(old, new, :movie)

      refute Enum.any?(events, &(&1.event_type == :new_season_announced))
      assert events == []
    end

    test "movie date change is still detected" do
      old = [
        build_tracking_release(%{
          season_number: nil,
          episode_number: nil,
          air_date: ~D[2026-05-22],
          title: "Sample Film"
        })
      ]

      new = [%{season_number: nil, episode_number: nil, air_date: ~D[2026-06-23], title: "Sample Film"}]

      assert [event] = Differ.diff(old, new, :movie)
      assert event.event_type == :upcoming_release_date_changed
      assert event.metadata.old_date == ~D[2026-05-22]
      assert event.metadata.new_date == ~D[2026-06-23]
    end

    test "movie removal is still detected" do
      old = [
        build_tracking_release(%{
          season_number: nil,
          episode_number: nil,
          air_date: ~D[2026-06-23],
          title: "Sample Film"
        })
      ]

      assert [event] = Differ.diff(old, [], :movie)
      assert event.event_type == :removed_from_schedule
    end
  end
end
