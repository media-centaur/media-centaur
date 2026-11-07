defmodule MediaCentaur.Library.PlaybackOverrideTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory
  alias MediaCentaur.Library
  alias MediaCentaur.Library.PlaybackOverride

  describe "get/3" do
    test "returns nil when no override exists" do
      tv_series = create_tv_series()
      assert Library.PlaybackOverrides.get(owner_profile_id(), :tv_series, tv_series.id) == nil
    end

    test "returns the override when it exists" do
      tv_series = create_tv_series()

      {:ok, _override} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :tv_series, tv_series.id, %{
          audio_lang: "jpn",
          subtitle_lang: "eng"
        })

      override = Library.PlaybackOverrides.get(owner_profile_id(), :tv_series, tv_series.id)
      assert %PlaybackOverride{audio_lang: "jpn", subtitle_lang: "eng"} = override
    end

    test "filters by owner_type — a tv_series and movie with the same id don't collide" do
      tv_series = create_tv_series()
      movie = create_movie(%{name: "Test Movie", id: tv_series.id})

      {:ok, _} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :tv_series, tv_series.id, %{
          audio_lang: "jpn"
        })

      {:ok, _} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :movie, movie.id, %{audio_lang: "fra"})

      assert %PlaybackOverride{audio_lang: "jpn"} =
               Library.PlaybackOverrides.get(owner_profile_id(), :tv_series, tv_series.id)

      assert %PlaybackOverride{audio_lang: "fra"} =
               Library.PlaybackOverrides.get(owner_profile_id(), :movie, movie.id)
    end
  end

  describe "settings — each follows its default on its own" do
    test "a setting is overridden only by its own fields" do
      subtitles_only = %PlaybackOverride{subtitle_lang: "spa"}

      refute PlaybackOverride.follows_default?(subtitles_only, :subtitles)
      assert PlaybackOverride.follows_default?(subtitles_only, :audio)
      assert PlaybackOverride.follows_default?(subtitles_only, :picture)
      refute PlaybackOverride.follows_default?(%PlaybackOverride{subtitles_off: true}, :subtitles)
      refute PlaybackOverride.follows_default?(%PlaybackOverride{fill_width: false}, :picture)
      assert PlaybackOverride.follows_default?(nil, :audio)
    end

    test "putting one setting on its default keeps the others" do
      movie_id = create_movie(%{name: "Test Movie"}).id

      {:ok, _} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :movie, movie_id, %{
          audio_lang: "jpn",
          subtitle_lang: "eng",
          fill_width: true
        })

      {:ok, override} =
        Library.PlaybackOverrides.upsert(
          owner_profile_id(),
          :movie,
          movie_id,
          PlaybackOverride.default_attrs(:subtitles)
        )

      assert override.audio_lang == "jpn"
      assert override.fill_width == true
      assert PlaybackOverride.follows_default?(override, :subtitles)
    end
  end

  describe "upsert/4" do
    test "creates a new override row for a tv_series" do
      tv_series = create_tv_series()

      {:ok, override} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :tv_series, tv_series.id, %{
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
        Library.PlaybackOverrides.upsert(owner_profile_id(), :movie, movie.id, %{
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
        Library.PlaybackOverrides.upsert(owner_profile_id(), :tv_series, tv_series.id, %{
          audio_lang: "jpn"
        })

      {:ok, second} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :tv_series, tv_series.id, %{
          audio_lang: "eng",
          subtitle_lang: "spa"
        })

      assert second.audio_lang == "eng"
      assert second.subtitle_lang == "spa"

      assert Repo.aggregate(PlaybackOverride, :count) == 1
    end

    test "stores a partial override — audio only, subtitle fields stay at nil" do
      tv_series = create_tv_series()

      {:ok, override} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :tv_series, tv_series.id, %{
          audio_lang: "jpn"
        })

      assert override.audio_lang == "jpn"
      assert override.subtitle_lang == nil
      assert override.subtitles_off == false
    end

    test "stores a partial override — subtitles_off=true with no subtitle_lang" do
      tv_series = create_tv_series()

      {:ok, override} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :tv_series, tv_series.id, %{
          subtitles_off: true
        })

      assert override.subtitles_off == true
      assert override.subtitle_lang == nil
    end

    test "rejects subtitles_off=true combined with a subtitle_lang" do
      tv_series = create_tv_series()

      {:error, changeset} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :tv_series, tv_series.id, %{
          subtitle_lang: "eng",
          subtitles_off: true
        })

      assert %{subtitles_off: ["cannot be true when subtitle_lang is set"]} =
               errors_on(changeset)
    end

    test "rejects an unknown owner_type" do
      assert {:error, changeset} =
               Library.PlaybackOverrides.upsert(
                 owner_profile_id(),
                 :episode,
                 Ecto.UUID.generate(),
                 %{audio_lang: "jpn"}
               )

      assert %{owner_type: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts a video_object owner — a standalone video remembers its tracks too" do
      video_object = create_video_object()

      assert {:ok, _override} =
               Library.PlaybackOverrides.upsert(owner_profile_id(), :video_object, video_object.id, %{
                 audio_lang: "jpn",
                 subtitle_lang: "eng"
               })

      assert %PlaybackOverride{audio_lang: "jpn", subtitle_lang: "eng"} =
               Library.PlaybackOverrides.get(owner_profile_id(), :video_object, video_object.id)
    end
  end

  describe "put_on_entity/2" do
    test "attaches the override under :playback_override for a movie entity" do
      movie = create_movie(%{name: "Test Movie"})

      {:ok, _} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :movie, movie.id, %{audio_lang: "jpn"})

      entity =
        Library.PlaybackOverrides.put_on_entity(owner_profile_id(), %{id: movie.id, type: :movie})

      assert %PlaybackOverride{audio_lang: "jpn"} = entity.playback_override
    end

    test "attaches nil when a movie entity has no override" do
      movie = create_movie(%{name: "Test Movie"})

      entity =
        Library.PlaybackOverrides.put_on_entity(owner_profile_id(), %{id: movie.id, type: :movie})

      assert Map.fetch!(entity, :playback_override) == nil
    end

    test "attaches the override for a tv_series entity" do
      tv_series = create_tv_series()

      {:ok, _} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :tv_series, tv_series.id, %{
          subtitle_lang: "eng"
        })

      entity =
        Library.PlaybackOverrides.put_on_entity(owner_profile_id(), %{
          id: tv_series.id,
          type: :tv_series
        })

      assert %PlaybackOverride{subtitle_lang: "eng"} = entity.playback_override
    end

    test "attaches nil for a non-overridable type even if a row shares the id" do
      movie = create_movie(%{name: "Test Movie"})

      {:ok, _} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :movie, movie.id, %{audio_lang: "jpn"})

      # movie_series is not a valid owner_type — the decorator must not
      # fetch under it, so the badge never leaks across container kinds.
      entity =
        Library.PlaybackOverrides.put_on_entity(owner_profile_id(), %{
          id: movie.id,
          type: :movie_series
        })

      assert Map.fetch!(entity, :playback_override) == nil
    end

    test "attaches nil when the entity map lacks id/type" do
      entity = Library.PlaybackOverrides.put_on_entity(owner_profile_id(), %{name: "orphan"})

      assert Map.fetch!(entity, :playback_override) == nil
    end

    test "preserves the rest of the entity map" do
      movie = create_movie(%{name: "Test Movie"})

      entity =
        Library.PlaybackOverrides.put_on_entity(owner_profile_id(), %{
          id: movie.id,
          type: :movie,
          name: "Kept"
        })

      assert entity.name == "Kept"
      assert entity.id == movie.id
    end
  end

  describe "clear/3" do
    test "deletes an existing override and returns :ok" do
      tv_series = create_tv_series()

      {:ok, _} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :tv_series, tv_series.id, %{
          audio_lang: "jpn"
        })

      assert :ok = Library.PlaybackOverrides.clear(owner_profile_id(), :tv_series, tv_series.id)
      assert Library.PlaybackOverrides.get(owner_profile_id(), :tv_series, tv_series.id) == nil
    end

    test "is a no-op when no override exists" do
      tv_series = create_tv_series()
      assert :ok = Library.PlaybackOverrides.clear(owner_profile_id(), :tv_series, tv_series.id)
    end

    test "only deletes the row matching the owner_type" do
      tv_series = create_tv_series()
      movie = create_movie(%{name: "Test Movie"})

      {:ok, _} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :tv_series, tv_series.id, %{
          audio_lang: "jpn"
        })

      {:ok, _} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :movie, movie.id, %{audio_lang: "fra"})

      assert :ok = Library.PlaybackOverrides.clear(owner_profile_id(), :tv_series, tv_series.id)
      assert Library.PlaybackOverrides.get(owner_profile_id(), :tv_series, tv_series.id) == nil

      assert %PlaybackOverride{audio_lang: "fra"} =
               Library.PlaybackOverrides.get(owner_profile_id(), :movie, movie.id)
    end
  end

  describe "two profiles" do
    test "the remembered tracks are the profile's own; clearing one leaves the other" do
      tv_series = create_tv_series()
      me = owner_profile_id()
      ana = create_profile(%{name: "Ana"}).id

      {:ok, _} = Library.PlaybackOverrides.upsert(me, :tv_series, tv_series.id, %{audio_lang: "jpn"})
      {:ok, _} = Library.PlaybackOverrides.upsert(ana, :tv_series, tv_series.id, %{audio_lang: "fra"})

      assert %PlaybackOverride{audio_lang: "jpn"} =
               Library.PlaybackOverrides.get(me, :tv_series, tv_series.id)

      assert %PlaybackOverride{audio_lang: "fra"} =
               Library.PlaybackOverrides.get(ana, :tv_series, tv_series.id)

      :ok = Library.PlaybackOverrides.clear(ana, :tv_series, tv_series.id)
      assert Library.PlaybackOverrides.get(ana, :tv_series, tv_series.id) == nil

      assert %PlaybackOverride{audio_lang: "jpn"} =
               Library.PlaybackOverrides.get(me, :tv_series, tv_series.id)

      entity = Library.PlaybackOverrides.put_on_entity(ana, %{id: tv_series.id, type: :tv_series})
      assert entity.playback_override == nil
    end
  end
end
