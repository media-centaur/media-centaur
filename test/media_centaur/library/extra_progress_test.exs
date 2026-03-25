defmodule MediaCentaur.Library.ExtraProgressTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library

  describe "find_or_create" do
    test "create and read back via :for_entity" do
      entity = create_entity(%{type: :movie, name: "Extra Progress Movie"})
      extra = create_extra(%{entity_id: entity.id, name: "Behind the Scenes"})

      create_extra_progress(%{
        extra_id: extra.id,
        entity_id: entity.id,
        position_seconds: 45.0,
        duration_seconds: 300.0
      })

      {:ok, [found]} = Library.list_extra_progress_for_entity(entity.id)

      assert found.extra_id == extra.id
      assert found.entity_id == entity.id
      assert found.position_seconds == 45.0
      assert found.duration_seconds == 300.0
      assert found.completed == false
      assert found.last_watched_at != nil
    end

    test "upsert updates position, no duplicate" do
      entity = create_entity(%{type: :movie, name: "Upsert Extra"})
      extra = create_extra(%{entity_id: entity.id, name: "Deleted Scene"})

      create_extra_progress(%{
        extra_id: extra.id,
        entity_id: entity.id,
        position_seconds: 10.0,
        duration_seconds: 120.0
      })

      create_extra_progress(%{
        extra_id: extra.id,
        entity_id: entity.id,
        position_seconds: 80.0,
        duration_seconds: 120.0
      })

      {:ok, records} = Library.list_extra_progress_for_entity(entity.id)

      assert length(records) == 1
      assert hd(records).position_seconds == 80.0
    end

    test "upsert preserves existing completed: true" do
      entity = create_entity(%{type: :movie, name: "Completed Extra"})
      extra = create_extra(%{entity_id: entity.id, name: "Featurette"})

      progress =
        create_extra_progress(%{
          extra_id: extra.id,
          entity_id: entity.id,
          position_seconds: 280.0,
          duration_seconds: 300.0
        })

      {:ok, _} = Library.mark_extra_completed(progress)

      create_extra_progress(%{
        extra_id: extra.id,
        entity_id: entity.id,
        position_seconds: 10.0,
        duration_seconds: 300.0
      })

      {:ok, [updated]} = Library.list_extra_progress_for_entity(entity.id)

      assert updated.completed == true
      assert updated.position_seconds == 10.0
    end

    test "multiple extras for same entity get separate records" do
      entity = create_entity(%{type: :movie, name: "Multi-Extra Movie"})
      extra_1 = create_extra(%{entity_id: entity.id, name: "BTS", position: 0})
      extra_2 = create_extra(%{entity_id: entity.id, name: "Deleted Scene", position: 1})

      create_extra_progress(%{
        extra_id: extra_1.id,
        entity_id: entity.id,
        position_seconds: 30.0,
        duration_seconds: 120.0
      })

      create_extra_progress(%{
        extra_id: extra_2.id,
        entity_id: entity.id,
        position_seconds: 60.0,
        duration_seconds: 180.0
      })

      {:ok, records} = Library.list_extra_progress_for_entity(entity.id)

      assert length(records) == 2
    end
  end

  describe "mark_completed" do
    test "transitions false to true" do
      entity = create_entity(%{type: :movie, name: "Complete Extra"})
      extra = create_extra(%{entity_id: entity.id, name: "BTS"})

      progress =
        create_extra_progress(%{
          extra_id: extra.id,
          entity_id: entity.id,
          position_seconds: 280.0,
          duration_seconds: 300.0
        })

      assert progress.completed == false

      {:ok, updated} = Library.mark_extra_completed(progress)
      assert updated.completed == true
    end
  end

  describe "mark_incomplete" do
    test "transitions completed from true to false" do
      entity = create_entity(%{type: :movie, name: "Incomplete Extra"})
      extra = create_extra(%{entity_id: entity.id, name: "BTS"})

      progress =
        create_extra_progress(%{
          extra_id: extra.id,
          entity_id: entity.id,
          position_seconds: 280.0,
          duration_seconds: 300.0
        })

      {:ok, completed} = Library.mark_extra_completed(progress)
      assert completed.completed == true

      {:ok, incomplete} = Library.mark_extra_incomplete(completed)
      assert incomplete.completed == false
    end
  end
end
