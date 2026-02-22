defmodule MediaManager.Library.WatchProgressTest do
  use MediaManager.DataCase

  alias MediaManager.Library.WatchProgress

  describe "WatchProgress" do
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

    test "auto-completion at 90% threshold" do
      entity = create_entity(%{type: :movie, name: "Almost Done"})

      progress =
        create_watch_progress(%{
          entity_id: entity.id,
          position_seconds: 6840.0,
          duration_seconds: 7200.0
        })

      assert progress.completed == true
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
  end
end
