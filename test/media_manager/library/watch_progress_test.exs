defmodule MediaManager.Library.WatchProgressTest do
  use MediaManager.DataCase

  alias MediaManager.Library.WatchProgress

  describe "upsert_progress" do
    test "create and read back via :for_entity" do
      entity = create_entity(%{type: :movie, name: "Progress Movie"})

      create_watch_progress(%{
        entity_id: entity.id,
        position_seconds: 120.5,
        duration_seconds: 7200.0
      })

      {:ok, [found]} =
        WatchProgress
        |> Ash.Query.for_read(:for_entity, %{entity_id: entity.id})
        |> Ash.read()

      assert found.entity_id == entity.id
      assert found.position_seconds == 120.5
      assert found.duration_seconds == 7200.0
      assert found.completed == false
      assert found.last_watched_at != nil
    end

    test "auto-completion at exactly 90% threshold" do
      entity = create_entity(%{type: :movie, name: "Exactly 90%"})

      progress =
        create_watch_progress(%{
          entity_id: entity.id,
          position_seconds: 6480.0,
          duration_seconds: 7200.0
        })

      # 6480 / 7200 = 0.90 exactly
      assert progress.completed == true
    end

    test "auto-completion above 90% threshold" do
      entity = create_entity(%{type: :movie, name: "Almost Done"})

      progress =
        create_watch_progress(%{
          entity_id: entity.id,
          position_seconds: 6840.0,
          duration_seconds: 7200.0
        })

      assert progress.completed == true
    end

    test "not completed just under 90% threshold" do
      entity = create_entity(%{type: :movie, name: "Still Watching"})

      progress =
        create_watch_progress(%{
          entity_id: entity.id,
          position_seconds: 6479.0,
          duration_seconds: 7200.0
        })

      # 6479 / 7200 ≈ 0.8998 < 0.90
      assert progress.completed == false
    end

    test "upsert idempotency — second upsert updates values, no duplicate" do
      entity = create_entity(%{type: :tv_series, name: "Upsert Show"})

      attrs = %{
        entity_id: entity.id,
        season_number: 1,
        episode_number: 3,
        position_seconds: 60.0,
        duration_seconds: 2400.0
      }

      create_watch_progress(attrs)
      create_watch_progress(%{attrs | position_seconds: 1200.0})

      {:ok, records} =
        WatchProgress
        |> Ash.Query.for_read(:for_entity, %{entity_id: entity.id})
        |> Ash.read()

      assert length(records) == 1
      assert hd(records).position_seconds == 1200.0
    end

    test "upsert updates last_watched_at timestamp" do
      entity = create_entity(%{type: :tv_series, name: "Timestamp Show"})

      first =
        create_watch_progress(%{
          entity_id: entity.id,
          season_number: 1,
          episode_number: 1,
          position_seconds: 60.0,
          duration_seconds: 2400.0
        })

      # Small delay to ensure timestamps differ
      Process.sleep(1100)

      create_watch_progress(%{
        entity_id: entity.id,
        season_number: 1,
        episode_number: 1,
        position_seconds: 300.0,
        duration_seconds: 2400.0
      })

      {:ok, [updated]} =
        WatchProgress
        |> Ash.Query.for_read(:for_entity, %{entity_id: entity.id})
        |> Ash.read()

      assert DateTime.compare(updated.last_watched_at, first.last_watched_at) in [:gt, :eq]
      assert updated.position_seconds == 300.0
    end

    test "multiple progress records for different episodes of same entity" do
      entity = create_entity(%{type: :tv_series, name: "Multi-Episode"})

      create_watch_progress(%{
        entity_id: entity.id,
        season_number: 1,
        episode_number: 1,
        position_seconds: 2400.0,
        duration_seconds: 2400.0
      })

      create_watch_progress(%{
        entity_id: entity.id,
        season_number: 1,
        episode_number: 2,
        position_seconds: 600.0,
        duration_seconds: 2400.0
      })

      {:ok, records} =
        WatchProgress
        |> Ash.Query.for_read(:for_entity, %{entity_id: entity.id})
        |> Ash.read()

      assert length(records) == 2
      [episode_1, episode_2] = Enum.sort_by(records, & &1.episode_number)
      assert episode_1.episode_number == 1
      assert episode_1.completed == true
      assert episode_2.episode_number == 2
      assert episode_2.completed == false
    end
  end

  describe "for_entity" do
    test "returns records sorted by season then episode" do
      entity = create_entity(%{type: :tv_series, name: "Sorted Show"})

      # Create out of order
      create_watch_progress(%{
        entity_id: entity.id,
        season_number: 2,
        episode_number: 1,
        position_seconds: 100.0,
        duration_seconds: 2400.0
      })

      create_watch_progress(%{
        entity_id: entity.id,
        season_number: 1,
        episode_number: 2,
        position_seconds: 200.0,
        duration_seconds: 2400.0
      })

      create_watch_progress(%{
        entity_id: entity.id,
        season_number: 1,
        episode_number: 1,
        position_seconds: 300.0,
        duration_seconds: 2400.0
      })

      {:ok, records} =
        WatchProgress
        |> Ash.Query.for_read(:for_entity, %{entity_id: entity.id})
        |> Ash.read()

      assert [{1, 1}, {1, 2}, {2, 1}] ==
               Enum.map(records, &{&1.season_number, &1.episode_number})
    end
  end
end
