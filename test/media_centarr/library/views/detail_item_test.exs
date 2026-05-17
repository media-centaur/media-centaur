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
      assert item.container_director == nil
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
      assert episode.images == []
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

  describe "to_entity_map/1 — TV series adapter (Phase 3.2 Task C.2)" do
    # The adapter is a temporary compatibility shim: it converts a TV-series
    # DetailItem (canonical-episode leaf carrying the entire series tree)
    # into the polymorphic-entity-map shape that `SeriesDetail.build/4`,
    # `ResumeTarget.compute/2`, and `EntityModal.{find_tmdb_id,
    # resolve_progress_fk}` consume today. Task E retires it.

    test "produces an entity map keyed to the TVSeries container, not the leaf" do
      detail_item = tv_series_detail_item()

      entity = DetailItem.to_entity_map(detail_item)

      assert entity.type == :tv_series
      assert entity.id == detail_item.parent_container_id
      assert entity.name == detail_item.container_name
    end

    test "passes container metadata through unchanged" do
      detail_item =
        tv_series_detail_item(
          container_description: "A sample show.",
          container_url: "https://tmdb.example/tv/1",
          container_tagline: "It's a sample.",
          container_genres: ["Drama"],
          container_studio: "Sample Studios",
          container_country_code: "US",
          container_original_language: "en",
          container_network: "Sample Network",
          container_status: :returning,
          container_duration_seconds: 1800,
          container_content_rating: "TV-14",
          container_aggregate_rating: 8.5,
          container_vote_count: 1234,
          container_number_of_seasons: 2
        )

      entity = DetailItem.to_entity_map(detail_item)

      assert entity.description == "A sample show."
      assert entity.url == "https://tmdb.example/tv/1"
      assert entity.tagline == "It's a sample."
      assert entity.genres == ["Drama"]
      assert entity.studio == "Sample Studios"
      assert entity.country_code == "US"
      assert entity.original_language == "en"
      assert entity.network == "Sample Network"
      assert entity.status == :returning
      assert entity.duration_seconds == 1800
      assert entity.content_rating == "TV-14"
      assert entity.aggregate_rating_value == 8.5
      assert entity.vote_count == 1234
      assert entity.number_of_seasons == 2
    end

    test "expands DetailItem.Season list into the rich season shape SeriesDetail.build/4 consumes" do
      season =
        %DetailItem.Season{
          season_number: 1,
          name: "Season 1",
          number_of_episodes: 3,
          extras: [%{id: "extra-1", name: "Season Recap"}],
          episodes: [
            %DetailItem.Episode{
              episode_id: "11111111-1111-1111-1111-111111111111",
              playable_item_id: "22222222-2222-2222-2222-222222222222",
              season_number: 1,
              episode_number: 1,
              name: "Pilot",
              description: "Pilot description",
              date_published: ~D[2020-01-01],
              duration_seconds: 1800,
              content_url: "/media/sample/s01e01.mkv",
              present?: true
            }
          ]
        }

      detail_item = tv_series_detail_item(seasons: [season])
      entity = DetailItem.to_entity_map(detail_item)

      assert [adapted_season] = entity.seasons
      assert adapted_season.season_number == 1
      assert adapted_season.name == "Season 1"
      assert adapted_season.number_of_episodes == 3
      assert [%{name: "Season Recap"}] = adapted_season.extras
      assert [adapted_episode] = adapted_season.episodes
      assert adapted_episode.id == "11111111-1111-1111-1111-111111111111"
      assert adapted_episode.episode_number == 1
      assert adapted_episode.name == "Pilot"
      assert adapted_episode.description == "Pilot description"
      assert adapted_episode.date_published == ~D[2020-01-01]
      assert adapted_episode.duration_seconds == 1800
      assert adapted_episode.content_url == "/media/sample/s01e01.mkv"
    end

    test "passes external_ids and imdb_id through; supports EntityModal.find_tmdb_id consumer" do
      detail_item =
        tv_series_detail_item(
          external_ids: [
            %{source: "tmdb", external_id: "42"},
            %{source: "imdb", external_id: "tt0000042"}
          ],
          imdb_id: "tt0000042",
          tmdb_id: "42"
        )

      entity = DetailItem.to_entity_map(detail_item)

      assert entity.imdb_id == "tt0000042"
      assert entity.tmdb_id == "42"
      assert [%{source: "tmdb", external_id: "42"}, %{source: "imdb"}] = entity.external_ids
    end

    test "defaults nil collections to empty lists so consumers can Enum.* safely" do
      detail_item =
        tv_series_detail_item(
          cast: nil,
          crew: nil,
          extras: nil,
          external_ids: nil,
          images: nil,
          seasons: nil
        )

      entity = DetailItem.to_entity_map(detail_item)

      assert entity.cast == []
      assert entity.crew == []
      assert entity.extras == []
      assert entity.external_ids == []
      assert entity.images == []
      assert entity.seasons == []
      assert entity.movies == []
      assert entity.watched_files == []
    end

    # --- Helpers ---

    defp tv_series_detail_item(overrides \\ []) do
      seasons = Keyword.get(overrides, :seasons, [])
      tv_series_id = "55555555-5555-5555-5555-555555555555"
      episode_id = "66666666-6666-6666-6666-666666666666"
      playable_item_id = "77777777-7777-7777-7777-777777777777"

      base = %DetailItem{
        playable_item_id: playable_item_id,
        container_type: :episode,
        container_id: episode_id,
        name: "Pilot",
        position: 1,
        parent_container_type: :tv_series,
        parent_container_id: tv_series_id,
        parent_container_name: "Sample Show",
        container_name: "Sample Show",
        container_description: nil,
        container_year: 2020,
        cast: [],
        crew: [],
        extras: [],
        external_ids: [],
        images: [],
        seasons: seasons,
        watched_files: [],
        subtitle_tracks: []
      }

      struct!(base, Map.new(overrides))
    end
  end

  describe "to_entity_map/1 — standalone Movie adapter (Phase 3.2 Task D)" do
    test "keys to the Movie container, type: :movie" do
      detail_item = movie_detail_item()
      entity = DetailItem.to_entity_map(detail_item)

      assert entity.type == :movie
      assert entity.id == detail_item.container_id
      assert entity.name == detail_item.container_name
    end

    test "carries Movie-specific :director facet field" do
      detail_item = movie_detail_item(container_director: "Sample Director")
      entity = DetailItem.to_entity_map(detail_item)
      assert entity.director == "Sample Director"
    end

    test "passes leaf date_published through (entity-level for solo movies)" do
      detail_item = movie_detail_item(date_published: ~D[2010-07-16])
      entity = DetailItem.to_entity_map(detail_item)
      assert entity.date_published == ~D[2010-07-16]
    end

    test "derives :content_url from the first :watched_files entry — Resume.resolve_single needs it" do
      files = [
        %DetailItem.WatchedFile{path: "/media/x/a.mkv", watch_dir: "/media/x"},
        %DetailItem.WatchedFile{path: "/media/x/b.mkv", watch_dir: "/media/x"}
      ]

      detail_item = movie_detail_item(watched_files: files)
      entity = DetailItem.to_entity_map(detail_item)
      assert entity.content_url == "/media/x/a.mkv"
    end

    test "content_url is nil when no WatchedFiles attach" do
      detail_item = movie_detail_item(watched_files: [])
      entity = DetailItem.to_entity_map(detail_item)
      assert entity.content_url == nil
    end

    test "preserves :subtitle_tracks for DetailPanel's subtitle-language render" do
      tracks = [
        %DetailItem.SubtitleTrack{kind: :embedded, language: "en", source: "stream:2"},
        %DetailItem.SubtitleTrack{kind: :sidecar, language: nil, source: "/x/forced.srt"}
      ]

      detail_item = movie_detail_item(subtitle_tracks: tracks)
      entity = DetailItem.to_entity_map(detail_item)
      assert entity.subtitle_tracks == tracks
    end

    test "defaults extra_progress to []" do
      detail_item = movie_detail_item()
      entity = DetailItem.to_entity_map(detail_item)
      assert entity.extra_progress == []
    end

    defp movie_detail_item(overrides \\ []) do
      base = %DetailItem{
        playable_item_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        container_type: :movie,
        container_id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
        name: "Sample Movie",
        position: 1,
        parent_container_type: nil,
        parent_container_id: nil,
        parent_container_name: nil,
        container_name: "Sample Movie",
        container_description: "A sample movie.",
        container_year: 2010,
        container_url: "https://tmdb.example/movie/1",
        container_tagline: nil,
        container_genres: ["Drama"],
        container_studio: nil,
        container_country_code: "US",
        container_original_language: "en",
        container_network: nil,
        container_status: nil,
        container_duration_seconds: 7200,
        container_content_rating: "PG-13",
        container_aggregate_rating: 7.5,
        container_vote_count: 100,
        container_number_of_seasons: nil,
        container_director: nil,
        cast: [],
        crew: [],
        extras: [],
        external_ids: [],
        images: [],
        seasons: nil,
        movies: nil,
        watched_files: [],
        subtitle_tracks: []
      }

      struct!(base, Map.new(overrides))
    end
  end

  describe "to_entity_map/1 — MovieSeries adapter (Phase 3.2 Task D)" do
    test "keys to the MovieSeries container (parent_container_id), type: :movie_series" do
      detail_item = movie_series_detail_item()
      entity = DetailItem.to_entity_map(detail_item)

      assert entity.type == :movie_series
      assert entity.id == detail_item.parent_container_id
      assert entity.name == detail_item.container_name
    end

    test "expands :movies list into the rich shape DetailPanel/build_facets consumes" do
      detail_item =
        movie_series_detail_item(
          movies: [
            %DetailItem.MovieEntry{
              movie_id: "11111111-1111-1111-1111-111111111111",
              playable_item_id: "22222222-2222-2222-2222-222222222222",
              name: "Sample Movie A",
              date_published: ~D[2010-01-01],
              collection_position: 1,
              content_url: "/media/saga/part-1.mkv",
              present?: true
            },
            %DetailItem.MovieEntry{
              movie_id: "33333333-3333-3333-3333-333333333333",
              playable_item_id: "44444444-4444-4444-4444-444444444444",
              name: "Sample Movie B",
              date_published: ~D[2012-01-01],
              collection_position: 2,
              content_url: "/media/saga/part-2.mkv",
              present?: true
            }
          ]
        )

      entity = DetailItem.to_entity_map(detail_item)

      assert [m1, m2] = entity.movies
      assert m1.id == "11111111-1111-1111-1111-111111111111"
      assert m1.name == "Sample Movie A"
      assert m1.date_published == ~D[2010-01-01]
      assert m1.content_url == "/media/saga/part-1.mkv"
      assert m2.name == "Sample Movie B"
    end

    test "empty :movies list when projection produced nothing" do
      detail_item = movie_series_detail_item(movies: nil)
      entity = DetailItem.to_entity_map(detail_item)
      assert entity.movies == []
    end

    defp movie_series_detail_item(overrides \\ []) do
      base = %DetailItem{
        playable_item_id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
        container_type: :movie,
        container_id: "dddddddd-dddd-dddd-dddd-dddddddddddd",
        name: "Sample Movie A",
        position: 1,
        parent_container_type: :movie_series,
        parent_container_id: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
        parent_container_name: "Sample Saga",
        container_name: "Sample Saga",
        container_description: "A sample movie collection.",
        container_year: 2010,
        container_url: nil,
        container_tagline: nil,
        container_genres: ["Adventure"],
        container_studio: nil,
        container_country_code: nil,
        container_original_language: nil,
        container_network: nil,
        container_status: nil,
        container_duration_seconds: nil,
        container_content_rating: nil,
        container_aggregate_rating: 8.0,
        container_vote_count: 500,
        container_number_of_seasons: nil,
        container_director: nil,
        cast: [],
        crew: [],
        extras: [],
        external_ids: [],
        images: [],
        seasons: nil,
        movies: [],
        watched_files: [],
        subtitle_tracks: []
      }

      struct!(base, Map.new(overrides))
    end
  end

  describe "to_entity_map/1 — VideoObject adapter (Phase 3.2 Task D)" do
    test "keys to the VideoObject container, type: :video_object" do
      detail_item = video_object_detail_item()
      entity = DetailItem.to_entity_map(detail_item)

      assert entity.type == :video_object
      assert entity.id == detail_item.container_id
      assert entity.name == detail_item.container_name
      assert entity.date_published == detail_item.date_published
    end

    defp video_object_detail_item do
      %DetailItem{
        playable_item_id: "ffffffff-ffff-ffff-ffff-ffffffffffff",
        container_type: :video_object,
        container_id: "01010101-0101-0101-0101-010101010101",
        name: "Sample Clip",
        position: 1,
        date_published: ~D[2024-06-01],
        parent_container_type: nil,
        parent_container_id: nil,
        parent_container_name: nil,
        container_name: "Sample Clip",
        container_description: "A sample standalone clip.",
        container_year: 2024,
        container_url: nil,
        container_tagline: nil,
        container_genres: nil,
        container_studio: nil,
        container_country_code: nil,
        container_original_language: nil,
        container_network: nil,
        container_status: nil,
        container_duration_seconds: 300,
        container_content_rating: nil,
        container_aggregate_rating: nil,
        container_vote_count: nil,
        container_number_of_seasons: nil,
        container_director: nil,
        cast: [],
        crew: [],
        extras: [],
        external_ids: [],
        images: [],
        seasons: nil,
        movies: nil,
        watched_files: [],
        subtitle_tracks: []
      }
    end
  end
end
