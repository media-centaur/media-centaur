defmodule MediaCentaur.Library.ExtraProgressTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library

  describe "find_or_create" do
    test "create and read back via extra_id" do
      movie = create_entity(%{type: :movie, name: "Extra Progress Movie"})
      extra = create_extra(%{movie_id: movie.id, name: "Behind the Scenes"})

      create_extra_progress(%{
        extra_id: extra.id,
        position_seconds: 45.0,
        duration_seconds: 300.0
      })

      {:ok, found} = Library.ProgressRecords.fetch_for_extra(extra.id)

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

      {:ok, found} = Library.ProgressRecords.fetch_for_extra(extra.id)
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

      {:ok, _} = Library.ProgressRecords.mark_completed(progress)

      create_extra_progress(%{
        extra_id: extra.id,
        position_seconds: 10.0,
        duration_seconds: 300.0
      })

      {:ok, updated} = Library.ProgressRecords.fetch_for_extra(extra.id)

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

      {:ok, found_1} = Library.ProgressRecords.fetch_for_extra(extra_1.id)
      {:ok, found_2} = Library.ProgressRecords.fetch_for_extra(extra_2.id)

      assert found_1.position_seconds == 30.0
      assert found_2.position_seconds == 60.0
    end

    test "returns :not_found for an extra with no progress row" do
      movie = create_entity(%{type: :movie, name: "Unwatched Extra Movie"})
      extra = create_extra(%{movie_id: movie.id, name: "Never Played"})

      assert Library.ProgressRecords.fetch_for_extra(extra.id) == {:error, :not_found}
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

      {:ok, updated} = Library.ProgressRecords.mark_completed(progress)
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

      {:ok, completed} = Library.ProgressRecords.mark_completed(progress)
      assert completed.completed == true

      {:ok, incomplete} = Library.ProgressRecords.mark_incomplete(completed)
      assert incomplete.completed == false
    end
  end
end
