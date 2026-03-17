defmodule MediaCentaur.Library.WatchProgressTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library

  describe "find_or_create" do
    test "create and read back via :for_entity" do
      entity = create_entity(%{type: :movie, name: "Progress Movie"})

      create_watch_progress(%{
        entity_id: entity.id,
        position_seconds: 120.5,
        duration_seconds: 7200.0
      })

      {:ok, [found]} = Library.list_watch_progress_for_entity(entity.id)

      assert found.entity_id == entity.id
      assert found.position_seconds == 120.5
      assert found.duration_seconds == 7200.0
      assert found.completed == false
      assert found.last_watched_at != nil
    end

    test "new record defaults completed to false" do
      entity = create_entity(%{type: :movie, name: "New Progress"})

      progress =
        create_watch_progress(%{
          entity_id: entity.id,
          position_seconds: 6840.0,
          duration_seconds: 7200.0
        })

      # Even at 95% position, upsert does not auto-complete
      assert progress.completed == false
    end

    test "upsert preserves existing completed: true" do
      entity = create_entity(%{type: :tv_series, name: "Completed Show"})

      # Create initial progress for a specific episode
      create_watch_progress(%{
        entity_id: entity.id,
        season_number: 1,
        episode_number: 1,
        position_seconds: 6480.0,
        duration_seconds: 7200.0
      })

      # Mark completed via dedicated action
      {:ok, [record]} = Library.list_watch_progress_for_entity(entity.id)

      {:ok, _} = Library.mark_watch_completed(record)

      # Now upsert with a lower position (re-watching from earlier)
      create_watch_progress(%{
        entity_id: entity.id,
        season_number: 1,
        episode_number: 1,
        position_seconds: 300.0,
        duration_seconds: 7200.0
      })

      {:ok, [updated]} = Library.list_watch_progress_for_entity(entity.id)

      # completed stays true — never regresses
      assert updated.completed == true
      assert updated.position_seconds == 300.0
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

      {:ok, records} = Library.list_watch_progress_for_entity(entity.id)

      assert length(records) == 1
      assert hd(records).position_seconds == 1200.0
    end

    test "upsert idempotency — movie (no season/episode) creates one record, not duplicates" do
      entity = create_entity(%{type: :movie, name: "Upsert Movie"})

      create_watch_progress(%{
        entity_id: entity.id,
        position_seconds: 35.0,
        duration_seconds: 7200.0
      })

      create_watch_progress(%{
        entity_id: entity.id,
        position_seconds: 3930.0,
        duration_seconds: 7200.0
      })

      {:ok, records} = Library.list_watch_progress_for_entity(entity.id)

      assert length(records) == 1
      assert hd(records).position_seconds == 3930.0
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

      {:ok, [updated]} = Library.list_watch_progress_for_entity(entity.id)

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

      {:ok, records} = Library.list_watch_progress_for_entity(entity.id)

      assert length(records) == 2
      [episode_1, episode_2] = Enum.sort_by(records, & &1.episode_number)
      assert episode_1.episode_number == 1
      assert episode_1.completed == false
      assert episode_2.episode_number == 2
      assert episode_2.completed == false
    end
  end

  describe "mark_completed" do
    test "transitions false to true" do
      entity = create_entity(%{type: :movie, name: "Mark Complete"})

      progress =
        create_watch_progress(%{
          entity_id: entity.id,
          position_seconds: 6480.0,
          duration_seconds: 7200.0
        })

      assert progress.completed == false

      {:ok, updated} = Library.mark_watch_completed(progress)
      assert updated.completed == true
    end

    test "updates last_watched_at" do
      entity = create_entity(%{type: :movie, name: "Mark Complete Timestamp"})

      progress =
        create_watch_progress(%{
          entity_id: entity.id,
          position_seconds: 100.0,
          duration_seconds: 7200.0
        })

      Process.sleep(1100)

      {:ok, updated} = Library.mark_watch_completed(progress)
      assert DateTime.compare(updated.last_watched_at, progress.last_watched_at) in [:gt, :eq]
    end
  end

  describe "mark_incomplete" do
    test "transitions completed from true to false" do
      entity = create_entity(%{type: :tv_series, name: "Unwatch Show"})

      progress =
        create_watch_progress(%{
          entity_id: entity.id,
          season_number: 1,
          episode_number: 1,
          position_seconds: 2400.0,
          duration_seconds: 2400.0
        })

      {:ok, completed} = Library.mark_watch_completed(progress)
      assert completed.completed == true

      {:ok, incomplete} = Library.mark_watch_incomplete(completed)
      assert incomplete.completed == false
      assert incomplete.last_watched_at != nil
    end

    test "updates last_watched_at" do
      entity = create_entity(%{type: :movie, name: "Unwatch Timestamp"})

      progress =
        create_watch_progress(%{
          entity_id: entity.id,
          position_seconds: 100.0,
          duration_seconds: 7200.0
        })

      {:ok, completed} = Library.mark_watch_completed(progress)
      Process.sleep(1100)

      {:ok, incomplete} = Library.mark_watch_incomplete(completed)
      assert DateTime.compare(incomplete.last_watched_at, completed.last_watched_at) in [:gt, :eq]
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

      {:ok, records} = Library.list_watch_progress_for_entity(entity.id)

      assert [{1, 1}, {1, 2}, {2, 1}] ==
               Enum.map(records, &{&1.season_number, &1.episode_number})
    end
  end
end
