defmodule MediaCentarr.Library.MediaTrackOverrideTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory
  alias MediaCentarr.Library
  alias MediaCentarr.Library.MediaTrackOverride

  describe "get_media_track_override/2" do
    test "returns nil when no override exists" do
      tv_series = create_tv_series()
      assert Library.get_media_track_override(:tv_series, tv_series.id) == nil
    end

    test "returns the override when it exists" do
      tv_series = create_tv_series()

      {:ok, _override} =
        Library.upsert_media_track_override(:tv_series, tv_series.id, %{
          audio_lang: "jpn",
          subtitle_lang: "eng"
        })

      override = Library.get_media_track_override(:tv_series, tv_series.id)
      assert %MediaTrackOverride{audio_lang: "jpn", subtitle_lang: "eng"} = override
    end

    test "filters by owner_type — a tv_series and movie with the same id don't collide" do
      tv_series = create_tv_series()
      movie = create_movie(%{name: "Test Movie", id: tv_series.id})

      {:ok, _} =
        Library.upsert_media_track_override(:tv_series, tv_series.id, %{audio_lang: "jpn"})

      {:ok, _} =
        Library.upsert_media_track_override(:movie, movie.id, %{audio_lang: "fra"})

      assert %MediaTrackOverride{audio_lang: "jpn"} =
               Library.get_media_track_override(:tv_series, tv_series.id)

      assert %MediaTrackOverride{audio_lang: "fra"} =
               Library.get_media_track_override(:movie, movie.id)
    end
  end

  describe "upsert_media_track_override/3" do
    test "creates a new override row for a tv_series" do
      tv_series = create_tv_series()

      {:ok, override} =
        Library.upsert_media_track_override(:tv_series, tv_series.id, %{
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
        Library.upsert_media_track_override(:movie, movie.id, %{
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
        Library.upsert_media_track_override(:tv_series, tv_series.id, %{audio_lang: "jpn"})

      {:ok, second} =
        Library.upsert_media_track_override(:tv_series, tv_series.id, %{
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
        Library.upsert_media_track_override(:tv_series, tv_series.id, %{audio_lang: "jpn"})

      assert override.audio_lang == "jpn"
      assert override.subtitle_lang == nil
      assert override.subtitles_off == false
    end

    test "stores a partial override — subtitles_off=true with no subtitle_lang" do
      tv_series = create_tv_series()

      {:ok, override} =
        Library.upsert_media_track_override(:tv_series, tv_series.id, %{subtitles_off: true})

      assert override.subtitles_off == true
      assert override.subtitle_lang == nil
    end

    test "rejects subtitles_off=true combined with a subtitle_lang" do
      tv_series = create_tv_series()

      {:error, changeset} =
        Library.upsert_media_track_override(:tv_series, tv_series.id, %{
          subtitle_lang: "eng",
          subtitles_off: true
        })

      assert %{subtitles_off: ["cannot be true when subtitle_lang is set"]} =
               errors_on(changeset)
    end

    test "rejects an unknown owner_type" do
      assert {:error, changeset} =
               Library.upsert_media_track_override(
                 :episode,
                 Ecto.UUID.generate(),
                 %{audio_lang: "jpn"}
               )

      assert %{owner_type: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "clear_media_track_override/2" do
    test "deletes an existing override and returns :ok" do
      tv_series = create_tv_series()
      {:ok, _} = Library.upsert_media_track_override(:tv_series, tv_series.id, %{audio_lang: "jpn"})

      assert :ok = Library.clear_media_track_override(:tv_series, tv_series.id)
      assert Library.get_media_track_override(:tv_series, tv_series.id) == nil
    end

    test "is a no-op when no override exists" do
      tv_series = create_tv_series()
      assert :ok = Library.clear_media_track_override(:tv_series, tv_series.id)
    end

    test "only deletes the row matching the owner_type" do
      tv_series = create_tv_series()
      movie = create_movie(%{name: "Test Movie"})

      {:ok, _} = Library.upsert_media_track_override(:tv_series, tv_series.id, %{audio_lang: "jpn"})
      {:ok, _} = Library.upsert_media_track_override(:movie, movie.id, %{audio_lang: "fra"})

      assert :ok = Library.clear_media_track_override(:tv_series, tv_series.id)
      assert Library.get_media_track_override(:tv_series, tv_series.id) == nil

      assert %MediaTrackOverride{audio_lang: "fra"} =
               Library.get_media_track_override(:movie, movie.id)
    end
  end
end
