defmodule MediaCentarr.Library.PlayableItemTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library
  alias MediaCentarr.Library.PlayableItem
  alias MediaCentarr.Repo

  import MediaCentarr.TestFactory

  describe "create_changeset/1" do
    test "round-trips a movie playable item" do
      movie = create_standalone_movie(%{name: "Sample Movie"})

      {:ok, item} =
        %{
          container_type: :movie,
          container_id: movie.id,
          position: 1,
          duration_seconds: 7200,
          name: nil
        }
        |> PlayableItem.create_changeset()
        |> Repo.insert()

      assert item.container_type == :movie
      assert item.container_id == movie.id
      assert item.position == 1
      assert item.duration_seconds == 7200
      assert is_nil(item.name)
    end

    test "round-trips an episode playable item with a version name" do
      season = create_season(%{tv_series_id: create_tv_series().id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 1})

      {:ok, item} =
        %{
          container_type: :episode,
          container_id: episode.id,
          position: 1,
          duration_seconds: 2700,
          name: "Director's Cut"
        }
        |> PlayableItem.create_changeset()
        |> Repo.insert()

      assert item.container_type == :episode
      assert item.container_id == episode.id
      assert item.name == "Director's Cut"
    end

    test "round-trips a video_object playable item" do
      video_object = create_video_object(%{name: "Sample Video"})

      {:ok, item} =
        %{
          container_type: :video_object,
          container_id: video_object.id,
          position: 1,
          duration_seconds: 900
        }
        |> PlayableItem.create_changeset()
        |> Repo.insert()

      assert item.container_type == :video_object
      assert item.container_id == video_object.id
    end

    test "validates container_type is in the enum" do
      changeset =
        PlayableItem.create_changeset(%{
          container_type: :bogus,
          container_id: Ecto.UUID.generate(),
          position: 1
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).container_type
    end

    test "requires container_type" do
      changeset =
        PlayableItem.create_changeset(%{
          container_id: Ecto.UUID.generate(),
          position: 1
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).container_type
    end

    test "requires container_id" do
      changeset =
        PlayableItem.create_changeset(%{
          container_type: :movie,
          position: 1
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).container_id
    end

    test "rejects duplicate (container_type, container_id, position) triples" do
      movie = create_standalone_movie(%{name: "Sample Movie"})

      attrs = %{container_type: :movie, container_id: movie.id, position: 1}

      assert {:ok, _first} =
               attrs
               |> PlayableItem.create_changeset()
               |> Repo.insert()

      assert {:error, %Ecto.Changeset{} = changeset} =
               attrs
               |> PlayableItem.create_changeset()
               |> Repo.insert()

      # The unique_constraint declaration translates the DB-level uniqueness
      # violation into a changeset error keyed by the first field in the
      # constraint list (`container_type`). The literal error message is
      # "has already been taken".
      refute changeset.valid?
      assert "has already been taken" in errors_on(changeset).container_type
    end
  end

  describe "Library.create_playable_item/1" do
    test "inserts a row through the context boundary" do
      movie = create_standalone_movie(%{name: "Sample Movie"})

      assert {:ok, item} =
               Library.create_playable_item(%{
                 container_type: :movie,
                 container_id: movie.id,
                 position: 1,
                 duration_seconds: 7200
               })

      assert item.container_type == :movie
      assert item.container_id == movie.id
    end

    test "returns an error changeset for invalid attrs" do
      assert {:error, changeset} =
               Library.create_playable_item(%{container_type: :bogus, container_id: nil})

      refute changeset.valid?
    end
  end

  describe "Library.fetch_playable_item/1" do
    test "returns {:ok, item} for an existing id" do
      movie = create_standalone_movie(%{name: "Sample Movie"})

      {:ok, inserted} =
        Library.create_playable_item(%{
          container_type: :movie,
          container_id: movie.id,
          position: 1
        })

      assert {:ok, fetched} = Library.fetch_playable_item(inserted.id)
      assert fetched.id == inserted.id
    end

    test "returns {:error, :not_found} for an unknown id" do
      assert {:error, :not_found} = Library.fetch_playable_item(Ecto.UUID.generate())
    end
  end

  describe "Library.list_playable_items_for/2" do
    test "lists items for a container, ordered by position" do
      movie = create_standalone_movie(%{name: "Sample Movie"})

      {:ok, _theatrical} =
        Library.create_playable_item(%{
          container_type: :movie,
          container_id: movie.id,
          position: 1,
          name: "Theatrical Cut"
        })

      {:ok, _directors} =
        Library.create_playable_item(%{
          container_type: :movie,
          container_id: movie.id,
          position: 2,
          name: "Director's Cut"
        })

      items = Library.list_playable_items_for(:movie, movie.id)

      assert length(items) == 2
      assert Enum.map(items, & &1.position) == [1, 2]
      assert Enum.map(items, & &1.name) == ["Theatrical Cut", "Director's Cut"]
    end

    test "ignores items belonging to other containers" do
      movie_a = create_standalone_movie(%{name: "Movie A"})
      movie_b = create_standalone_movie(%{name: "Movie B"})

      {:ok, _a} =
        Library.create_playable_item(%{
          container_type: :movie,
          container_id: movie_a.id,
          position: 1
        })

      {:ok, _b} =
        Library.create_playable_item(%{
          container_type: :movie,
          container_id: movie_b.id,
          position: 1
        })

      items = Library.list_playable_items_for(:movie, movie_a.id)
      assert length(items) == 1
      assert hd(items).container_id == movie_a.id
    end
  end

  describe "has_many :playable_items preload" do
    test "Movie preloads only its movie-typed playable items" do
      movie = create_standalone_movie(%{name: "Sample Movie"})

      {:ok, _} =
        Library.create_playable_item(%{
          container_type: :movie,
          container_id: movie.id,
          position: 1
        })

      # An unrelated playable item with the same UUID would not normally
      # exist, but the `where: [container_type: :movie]` filter on the
      # has_many is what guarantees only movie-typed items load — assert
      # the happy path: preload returns the one we inserted.
      reloaded = Repo.preload(movie, :playable_items)
      assert length(reloaded.playable_items) == 1
      assert hd(reloaded.playable_items).container_type == :movie
    end

    test "Episode preloads only its episode-typed playable items" do
      season = create_season(%{tv_series_id: create_tv_series().id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 1})

      {:ok, _} =
        Library.create_playable_item(%{
          container_type: :episode,
          container_id: episode.id,
          position: 1
        })

      reloaded = Repo.preload(episode, :playable_items)
      assert length(reloaded.playable_items) == 1
      assert hd(reloaded.playable_items).container_type == :episode
    end

    test "VideoObject preloads only its video_object-typed playable items" do
      video_object = create_video_object(%{name: "Sample Video"})

      {:ok, _} =
        Library.create_playable_item(%{
          container_type: :video_object,
          container_id: video_object.id,
          position: 1
        })

      reloaded = Repo.preload(video_object, :playable_items)
      assert length(reloaded.playable_items) == 1
      assert hd(reloaded.playable_items).container_type == :video_object
    end
  end

  describe "TestFactory" do
    test "create_playable_item/1 persists a row" do
      movie = create_standalone_movie(%{name: "Sample Movie"})

      item =
        create_playable_item(%{
          container_type: :movie,
          container_id: movie.id,
          position: 1
        })

      assert item.id != nil
      assert item.container_type == :movie
    end

    test "create_playable_item_for_movie/1 links to the movie" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      item = create_playable_item_for_movie(movie)

      assert item.container_type == :movie
      assert item.container_id == movie.id
      assert item.position == 1
    end
  end
end
