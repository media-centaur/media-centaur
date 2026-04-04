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
      assert event.event_type == :date_changed
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
      assert event.event_type == :date_changed
      assert String.contains?(event.description, "removed")
    end
  end
end
