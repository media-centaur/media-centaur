defmodule MediaCentarr.Library.ExtraProgressTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library

  describe "find_or_create" do
    test "create and read back via extra_id" do
      movie = create_entity(%{type: :movie, name: "Extra Progress Movie"})
      extra = create_extra(%{movie_id: movie.id, name: "Behind the Scenes"})

      create_extra_progress(%{
        extra_id: extra.id,
        position_seconds: 45.0,
        duration_seconds: 300.0
      })

      found = Library.get_extra_progress_by_extra(extra.id)

      assert found.extra_id == extra.id
      assert found.position_seconds == 45.0
      assert found.duration_seconds == 300.0
      assert found.completed == false
      assert found.last_watched_at != nil
    end

    test "upsert updates position, no duplicate" do
      movie = create_entity(%{type: :movie, name: "Upsert Extra"})
      extra = create_extra(%{movie_id: movie.id, name: "Deleted Scene"})

      create_extra_progress(%{
        extra_id: extra.id,
        position_seconds: 10.0,
        duration_seconds: 120.0
      })

      create_extra_progress(%{
        extra_id: extra.id,
        position_seconds: 80.0,
        duration_seconds: 120.0
      })

      found = Library.get_extra_progress_by_extra(extra.id)
      assert found.position_seconds == 80.0
    end

    test "upsert preserves existing completed: true" do
      movie = create_entity(%{type: :movie, name: "Completed Extra"})
      extra = create_extra(%{movie_id: movie.id, name: "Featurette"})

      progress =
        create_extra_progress(%{
          extra_id: extra.id,
          position_seconds: 280.0,
          duration_seconds: 300.0
        })

      {:ok, _} = Library.mark_extra_completed(progress)

      create_extra_progress(%{
        extra_id: extra.id,
        position_seconds: 10.0,
        duration_seconds: 300.0
      })

      updated = Library.get_extra_progress_by_extra(extra.id)

      assert updated.completed == true
      assert updated.position_seconds == 10.0
    end

    test "multiple extras for same entity get separate records" do
      movie = create_entity(%{type: :movie, name: "Multi-Extra Movie"})
      extra_1 = create_extra(%{movie_id: movie.id, name: "BTS", position: 0})
      extra_2 = create_extra(%{movie_id: movie.id, name: "Deleted Scene", position: 1})

      create_extra_progress(%{
        extra_id: extra_1.id,
        position_seconds: 30.0,
        duration_seconds: 120.0
      })

      create_extra_progress(%{
        extra_id: extra_2.id,
        position_seconds: 60.0,
        duration_seconds: 180.0
      })

      found_1 = Library.get_extra_progress_by_extra(extra_1.id)
      found_2 = Library.get_extra_progress_by_extra(extra_2.id)

      assert found_1 != nil
      assert found_2 != nil
    end
  end

  describe "mark_completed" do
    test "transitions false to true" do
      movie = create_entity(%{type: :movie, name: "Complete Extra"})
      extra = create_extra(%{movie_id: movie.id, name: "BTS"})

      progress =
        create_extra_progress(%{
          extra_id: extra.id,
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
      movie = create_entity(%{type: :movie, name: "Incomplete Extra"})
      extra = create_extra(%{movie_id: movie.id, name: "BTS"})

      progress =
        create_extra_progress(%{
          extra_id: extra.id,
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
