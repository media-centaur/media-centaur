defmodule MediaCentaur.WatchHistory.EventTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.WatchHistory.Event

  describe "create_changeset/1" do
    test "valid attrs produce a valid changeset" do
      attrs = %{
        entity_type: :movie,
        title: "Sample Movie Thirteen",
        duration_seconds: 9360.0,
        completed_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      changeset = Event.create_changeset(attrs)
      assert changeset.valid?
    end

    test "requires entity_type, title, duration_seconds, and completed_at" do
      changeset = Event.create_changeset(%{})
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :entity_type)
      assert Keyword.has_key?(changeset.errors, :title)
      assert Keyword.has_key?(changeset.errors, :duration_seconds)
      assert Keyword.has_key?(changeset.errors, :completed_at)
    end

    test "entity_type rejects unknown values" do
      attrs = %{
        entity_type: :book,
        title: "X",
        duration_seconds: 0.0,
        completed_at: DateTime.utc_now()
      }

      changeset = Event.create_changeset(attrs)
      refute changeset.valid?
    end
  end

  describe "nilify_all on entity deletion" do
    test "movie_id is nilified when movie is deleted" do
      movie = create_movie(%{name: "Sample Movie"})

      {:ok, event} =
        Event.create_changeset(%{
          entity_type: :movie,
          movie_id: movie.id,
          title: "Sample Movie",
          duration_seconds: 7080.0,
          completed_at: DateTime.truncate(DateTime.utc_now(), :second)
        })
        |> MediaCentaur.Repo.insert()

      MediaCentaur.Repo.delete!(movie)
      reloaded = MediaCentaur.Repo.get!(Event, event.id)

      assert reloaded.movie_id == nil
      assert reloaded.title == "Sample Movie"
    end
  end
end
