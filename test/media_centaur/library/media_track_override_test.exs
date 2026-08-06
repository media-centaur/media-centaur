defmodule MediaCentaur.Library.MediaTrackOverrideTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory
  alias MediaCentaur.Library
  alias MediaCentaur.Library.MediaTrackOverride

  describe "get_media_track_override/2" do
    test "returns nil when no override exists" do
      tv_series = create_tv_series()
      assert Library.MediaTrackOverrides.get(:tv_series, tv_series.id) == nil
    end

    test "returns the override when it exists" do
      tv_series = create_tv_series()

      {:ok, _override} =
        Library.MediaTrackOverrides.upsert(:tv_series, tv_series.id, %{
          audio_lang: "jpn",
          subtitle_lang: "eng"
        })

      override = Library.MediaTrackOverrides.get(:tv_series, tv_series.id)
      assert %MediaTrackOverride{audio_lang: "jpn", subtitle_lang: "eng"} = override
    end

    test "filters by owner_type — a tv_series and movie with the same id don't collide" do
      tv_series = create_tv_series()
      movie = create_movie(%{name: "Test Movie", id: tv_series.id})

      {:ok, _} =
        Library.MediaTrackOverrides.upsert(:tv_series, tv_series.id, %{audio_lang: "jpn"})

      {:ok, _} =
        Library.MediaTrackOverrides.upsert(:movie, movie.id, %{audio_lang: "fra"})

      assert %MediaTrackOverride{audio_lang: "jpn"} =
               Library.MediaTrackOverrides.get(:tv_series, tv_series.id)

      assert %MediaTrackOverride{audio_lang: "fra"} =
               Library.MediaTrackOverrides.get(:movie, movie.id)
    end
  end

  describe "upsert_media_track_override/3" do
    test "creates a new override row for a tv_series" do
      tv_series = create_tv_series()

      {:ok, override} =
        Library.MediaTrackOverrides.upsert(:tv_series, tv_series.id, %{
          audio_lang: "jpn",
          subtitle_lang: "eng"
        })

      assert override.owner_type == :tv_series
      assert override.owner_id == tv_series.id
      assert override.audio_lang == "jpn"
      assert override.subtitle_lang == "eng"
      assert override.subtitle_forced == false
      assert override.subtitles_off == false
    end

    test "creates a new override row for a movie" do
      movie = create_movie(%{name: "Test Movie"})

      {:ok, override} =
        Library.MediaTrackOverrides.upsert(:movie, movie.id, %{
          audio_lang: "fra",
          subtitle_lang: "eng",
          subtitle_forced: true
        })

      assert override.owner_type == :movie
      assert override.owner_id == movie.id
      assert override.audio_lang == "fra"
      assert override.subtitle_forced == true
    end

    test "updates an existing override in place (single row maintained per entity)" do
      tv_series = create_tv_series()

      {:ok, _first} =
        Library.MediaTrackOverrides.upsert(:tv_series, tv_series.id, %{audio_lang: "jpn"})

      {:ok, second} =
        Library.MediaTrackOverrides.upsert(:tv_series, tv_series.id, %{
          audio_lang: "eng",
          subtitle_lang: "spa"
        })

      assert second.audio_lang == "eng"
      assert second.subtitle_lang == "spa"

      assert Repo.aggregate(MediaTrackOverride, :count) == 1
    end

    test "stores a partial override — audio only, subtitle fields stay at nil" do
      tv_series = create_tv_series()

      {:ok, override} =
        Library.MediaTrackOverrides.upsert(:tv_series, tv_series.id, %{audio_lang: "jpn"})

      assert override.audio_lang == "jpn"
      assert override.subtitle_lang == nil
      assert override.subtitles_off == false
    end

    test "stores a partial override — subtitles_off=true with no subtitle_lang" do
      tv_series = create_tv_series()

      {:ok, override} =
        Library.MediaTrackOverrides.upsert(:tv_series, tv_series.id, %{subtitles_off: true})

      assert override.subtitles_off == true
      assert override.subtitle_lang == nil
    end

    test "rejects subtitles_off=true combined with a subtitle_lang" do
      tv_series = create_tv_series()

      {:error, changeset} =
        Library.MediaTrackOverrides.upsert(:tv_series, tv_series.id, %{
          subtitle_lang: "eng",
          subtitles_off: true
        })

      assert %{subtitles_off: ["cannot be true when subtitle_lang is set"]} =
               errors_on(changeset)
    end

    test "rejects an unknown owner_type" do
      assert {:error, changeset} =
               Library.MediaTrackOverrides.upsert(
                 :episode,
                 Ecto.UUID.generate(),
                 %{audio_lang: "jpn"}
               )

      assert %{owner_type: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts a video_object owner — a standalone video remembers its tracks too" do
      video_object = create_video_object()

      assert {:ok, _override} =
               Library.MediaTrackOverrides.upsert(:video_object, video_object.id, %{
                 audio_lang: "jpn",
                 subtitle_lang: "eng"
               })

      assert %MediaTrackOverride{audio_lang: "jpn", subtitle_lang: "eng"} =
               Library.MediaTrackOverrides.get(:video_object, video_object.id)
    end
  end

  describe "put_track_override/1" do
    test "attaches the override under :track_override for a movie entity" do
      movie = create_movie(%{name: "Test Movie"})
      {:ok, _} = Library.MediaTrackOverrides.upsert(:movie, movie.id, %{audio_lang: "jpn"})

      entity = Library.MediaTrackOverrides.put_on_entity(%{id: movie.id, type: :movie})

      assert %MediaTrackOverride{audio_lang: "jpn"} = entity.track_override
    end

    test "attaches nil when a movie entity has no override" do
      movie = create_movie(%{name: "Test Movie"})

      entity = Library.MediaTrackOverrides.put_on_entity(%{id: movie.id, type: :movie})

      assert Map.fetch!(entity, :track_override) == nil
    end

    test "attaches the override for a tv_series entity" do
      tv_series = create_tv_series()
      {:ok, _} = Library.MediaTrackOverrides.upsert(:tv_series, tv_series.id, %{subtitle_lang: "eng"})

      entity = Library.MediaTrackOverrides.put_on_entity(%{id: tv_series.id, type: :tv_series})

      assert %MediaTrackOverride{subtitle_lang: "eng"} = entity.track_override
    end

    test "attaches nil for a non-overridable type even if a row shares the id" do
      movie = create_movie(%{name: "Test Movie"})
      {:ok, _} = Library.MediaTrackOverrides.upsert(:movie, movie.id, %{audio_lang: "jpn"})

      # movie_series is not a valid owner_type — the decorator must not
      # fetch under it, so the badge never leaks across container kinds.
      entity = Library.MediaTrackOverrides.put_on_entity(%{id: movie.id, type: :movie_series})

      assert Map.fetch!(entity, :track_override) == nil
    end

    test "attaches nil when the entity map lacks id/type" do
      entity = Library.MediaTrackOverrides.put_on_entity(%{name: "orphan"})

      assert Map.fetch!(entity, :track_override) == nil
    end

    test "preserves the rest of the entity map" do
      movie = create_movie(%{name: "Test Movie"})

      entity = Library.MediaTrackOverrides.put_on_entity(%{id: movie.id, type: :movie, name: "Kept"})

      assert entity.name == "Kept"
      assert entity.id == movie.id
    end
  end

  describe "clear_media_track_override/2" do
    test "deletes an existing override and returns :ok" do
      tv_series = create_tv_series()
      {:ok, _} = Library.MediaTrackOverrides.upsert(:tv_series, tv_series.id, %{audio_lang: "jpn"})

      assert :ok = Library.MediaTrackOverrides.clear(:tv_series, tv_series.id)
      assert Library.MediaTrackOverrides.get(:tv_series, tv_series.id) == nil
    end

    test "is a no-op when no override exists" do
      tv_series = create_tv_series()
      assert :ok = Library.MediaTrackOverrides.clear(:tv_series, tv_series.id)
    end

    test "only deletes the row matching the owner_type" do
      tv_series = create_tv_series()
      movie = create_movie(%{name: "Test Movie"})

      {:ok, _} = Library.MediaTrackOverrides.upsert(:tv_series, tv_series.id, %{audio_lang: "jpn"})
      {:ok, _} = Library.MediaTrackOverrides.upsert(:movie, movie.id, %{audio_lang: "fra"})

      assert :ok = Library.MediaTrackOverrides.clear(:tv_series, tv_series.id)
      assert Library.MediaTrackOverrides.get(:tv_series, tv_series.id) == nil

      assert %MediaTrackOverride{audio_lang: "fra"} =
               Library.MediaTrackOverrides.get(:movie, movie.id)
    end
  end
end
