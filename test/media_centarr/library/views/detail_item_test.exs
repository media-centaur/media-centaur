defmodule MediaCentarr.Library.Views.DetailItemTest do
  @moduledoc """
  Struct-shape spec for `Library.Views.DetailItem` and its nested
  view-model structs introduced in Library Schema v2 Phase 3.2.

  The projection (`Library.Views.Detail`) populates these; consumers
  (DetailPanel and its sub-components) read from these. Per ADR-041,
  the struct shape is the typed contract between the two — every
  field a consumer reads must be declared here, every field declared
  here must be populated by the projection.

  Progress data is intentionally NOT carried on these structs.
  Position ticks during playback would otherwise invalidate the
  projection on every flush — same overlay pattern Phase 3.1
  established for `BrowseItem` (consumed alongside
  `Library.list_progress_summaries/1`).
  """
  use ExUnit.Case, async: true

  alias MediaCentarr.Library.Views.DetailItem

  describe "DetailItem struct shape (Phase 3.2 expansion)" do
    test "declares the new fields with default values" do
      item = %DetailItem{
        playable_item_id: "00000000-0000-0000-0000-000000000001",
        container_type: :movie,
        container_id: "00000000-0000-0000-0000-000000000002",
        name: "Sample Movie"
      }

      assert item.images == nil
      assert item.seasons == nil
      assert item.movies == nil
      assert item.watched_files == nil
      assert item.subtitle_tracks == nil
    end

    test "still enforces the existing required keys" do
      assert_raise ArgumentError, fn ->
        struct!(DetailItem, %{name: "Missing keys"})
      end
    end
  end

  describe "DetailItem.Season" do
    test "is constructable with required keys" do
      season = %DetailItem.Season{
        season_number: 1,
        episodes: []
      }

      assert season.season_number == 1
      assert season.name == nil
      assert season.episodes == []
      assert season.extras == []
      assert season.number_of_episodes == nil
    end

    test "enforces season_number and episodes" do
      assert_raise ArgumentError, fn ->
        struct!(DetailItem.Season, %{name: "Season One"})
      end
    end
  end

  describe "DetailItem.Episode" do
    test "is constructable with required keys" do
      episode = %DetailItem.Episode{
        episode_id: "00000000-0000-0000-0000-000000000010",
        playable_item_id: "00000000-0000-0000-0000-000000000011",
        season_number: 1,
        episode_number: 1,
        name: "Pilot"
      }

      assert episode.episode_id == "00000000-0000-0000-0000-000000000010"
      assert episode.playable_item_id == "00000000-0000-0000-0000-000000000011"
      assert episode.season_number == 1
      assert episode.episode_number == 1
      assert episode.name == "Pilot"
      assert episode.description == nil
      assert episode.date_published == nil
      assert episode.duration_seconds == nil
      assert episode.present? == nil
      assert episode.content_url == nil
    end

    test "enforces episode_id, playable_item_id, season_number, episode_number, name" do
      assert_raise ArgumentError, fn ->
        struct!(DetailItem.Episode, %{name: "No keys"})
      end
    end
  end

  describe "DetailItem.MovieEntry" do
    test "is constructable with required keys" do
      entry = %DetailItem.MovieEntry{
        movie_id: "00000000-0000-0000-0000-000000000020",
        playable_item_id: "00000000-0000-0000-0000-000000000021",
        name: "Sample Movie A"
      }

      assert entry.movie_id == "00000000-0000-0000-0000-000000000020"
      assert entry.playable_item_id == "00000000-0000-0000-0000-000000000021"
      assert entry.name == "Sample Movie A"
      assert entry.date_published == nil
      assert entry.collection_position == nil
      assert entry.content_url == nil
      assert entry.present? == nil
    end

    test "enforces movie_id, playable_item_id, name" do
      assert_raise ArgumentError, fn ->
        struct!(DetailItem.MovieEntry, %{date_published: ~D[2020-01-01]})
      end
    end
  end

  describe "DetailItem.WatchedFile" do
    test "is constructable with required keys" do
      file = %DetailItem.WatchedFile{
        path: "/media/movies/sample.mkv",
        watch_dir: "/media/movies"
      }

      assert file.path == "/media/movies/sample.mkv"
      assert file.watch_dir == "/media/movies"
    end

    test "enforces path and watch_dir" do
      assert_raise ArgumentError, fn ->
        struct!(DetailItem.WatchedFile, %{})
      end
    end
  end

  describe "DetailItem.SubtitleTrack" do
    test "is constructable with required keys" do
      track = %DetailItem.SubtitleTrack{
        kind: :embedded,
        language: "eng"
      }

      assert track.kind == :embedded
      assert track.language == "eng"
      assert track.source == nil
    end

    test "enforces kind and language" do
      assert_raise ArgumentError, fn ->
        struct!(DetailItem.SubtitleTrack, %{source: "stream-0"})
      end
    end
  end
end
