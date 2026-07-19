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
    # (the I Love Boosters bug). A movie has no season to announce — a newly
    # scheduled movie release is announced as `:release_scheduled` instead.
    test "movie release addition is announced as scheduled, never a season" do
      old = []
      # Future-dated — the Differ announces genuinely upcoming releases as
      # scheduled; an already-aired date is not (`released` derives from it).
      future = Date.add(Date.utc_today(), 60)

      new = [
        %{
          season_number: nil,
          episode_number: nil,
          air_date: future,
          title: "Sample Film",
          release_type: "theatrical"
        }
      ]

      events = Differ.diff(old, new, :movie)

      refute Enum.any?(events, &(&1.event_type == :new_season_announced))
      assert [event] = events
      assert event.event_type == :release_scheduled
      assert event.metadata.title == "Sample Film"
      assert event.metadata.air_date == future
    end

    # Regression: a movie's theatrical/digital/physical dates share
    # {season, episode, title} = {nil, nil, title}, so they collapsed (last-wins)
    # in the differ index — a genuinely new typed date was misread as the lone
    # release's date *changing*. Keying on release_type keeps them distinct.
    test "a new typed release is an addition, not a date change (no collapse)" do
      old = [
        build_tracking_release(%{
          season_number: nil,
          episode_number: nil,
          air_date: ~D[2026-06-23],
          title: "Sample Film",
          release_type: "theatrical"
        })
      ]

      new = [
        %{
          season_number: nil,
          episode_number: nil,
          air_date: ~D[2026-06-23],
          title: "Sample Film",
          release_type: "theatrical"
        },
        %{
          season_number: nil,
          episode_number: nil,
          air_date: ~D[2026-09-01],
          title: "Sample Film",
          release_type: "digital"
        }
      ]

      events = Differ.diff(old, new, :movie)

      refute Enum.any?(events, &(&1.event_type == :upcoming_release_date_changed))
      assert [event] = events
      assert event.event_type == :release_scheduled
      assert event.metadata.air_date == ~D[2026-09-01]
    end

    test "an undated movie release is not announced" do
      old = []

      new = [
        %{
          season_number: nil,
          episode_number: nil,
          air_date: nil,
          title: "Sample Film",
          release_type: "theatrical"
        }
      ]

      assert [] = Differ.diff(old, new, :movie)
    end

    test "an already-released movie addition is not announced" do
      old = []

      new = [
        %{
          season_number: nil,
          episode_number: nil,
          air_date: ~D[2026-01-01],
          title: "Sample Film",
          release_type: "theatrical",
          released: true
        }
      ]

      assert [] = Differ.diff(old, new, :movie)
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
