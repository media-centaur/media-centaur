defmodule MediaCentarrWeb.LibraryHelpersTest do
  use ExUnit.Case, async: true

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library.Views.BrowseItem
  alias MediaCentarrWeb.LibraryAvailability
  alias MediaCentarrWeb.LibraryFormatters
  alias MediaCentarrWeb.LibraryHelpers
  alias MediaCentarrWeb.LibraryProgress

  # --- Helpers ---

  defp item(overrides) do
    defaults = %{
      id: Map.get(overrides, :id, "id-#{System.unique_integer([:positive])}"),
      kind: Map.get(overrides, :kind, :movie),
      name: Map.get(overrides, :name, "Sample"),
      date_published: Map.get(overrides, :date_published),
      year: Map.get(overrides, :year),
      poster_url: Map.get(overrides, :poster_url),
      present?: Map.get(overrides, :present?, true),
      rank: Map.get(overrides, :rank)
    }

    struct!(BrowseItem, defaults)
  end

  # --- filtered_by_tab/2 ---

  describe "filtered_by_tab/2" do
    test "returns all entries for :all" do
      entries = [item(%{kind: :movie}), item(%{kind: :tv_series})]
      assert LibraryHelpers.filtered_by_tab(entries, :all) == entries
    end

    test "filters to movies / movie_series / video_object for :movies" do
      movie = item(%{id: "a", kind: :movie, name: "A"})
      series = item(%{id: "b", kind: :movie_series, name: "B"})
      video = item(%{id: "c", kind: :video_object, name: "C"})
      tv = item(%{id: "d", kind: :tv_series, name: "D"})

      result = LibraryHelpers.filtered_by_tab([movie, series, video, tv], :movies)
      assert Enum.map(result, & &1.name) == ["A", "B", "C"]
    end

    test "filters to tv_series for :tv" do
      movie = item(%{kind: :movie, name: "A"})
      tv = item(%{kind: :tv_series, name: "B"})

      result = LibraryHelpers.filtered_by_tab([movie, tv], :tv)
      assert length(result) == 1
      assert hd(result).name == "B"
    end
  end

  # --- filtered_by_text/2 ---

  describe "filtered_by_text/2" do
    test "returns all entries for empty string" do
      entries = [item(%{name: "Anything"})]
      assert LibraryHelpers.filtered_by_text(entries, "") == entries
    end

    test "matches BrowseItem.name case-insensitively" do
      match = item(%{name: "Sample Show"})
      miss = item(%{name: "Other Show"})

      result = LibraryHelpers.filtered_by_text([match, miss], "sample")
      assert length(result) == 1
      assert hd(result).name == "Sample Show"
    end

    test "returns empty list when nothing matches" do
      entries = [item(%{name: "Sample Show"})]
      assert LibraryHelpers.filtered_by_text(entries, "nonexistent") == []
    end
  end

  # --- filtered_by_in_progress/3 ---

  describe "filtered_by_in_progress/3" do
    test "returns entries unchanged when filter is false" do
      entries = [item(%{}), item(%{})]
      assert LibraryHelpers.filtered_by_in_progress(entries, %{}, false) == entries
    end

    test "keeps entries with an incomplete summary, drops finished ones" do
      a = item(%{id: "a"})
      b = item(%{id: "b"})
      c = item(%{id: "c"})

      progress_by_id = %{
        "a" => %{episodes_completed: 1, episodes_total: 10},
        "b" => %{episodes_completed: 10, episodes_total: 10}
        # "c" — no record; filtered out as not in-progress.
      }

      result = LibraryHelpers.filtered_by_in_progress([a, b, c], progress_by_id, true)
      assert Enum.map(result, & &1.id) == ["a"]
    end
  end

  # --- sorted_by/2 ---

  describe "sorted_by/2" do
    test "sorts alphabetically by name" do
      entries = [
        item(%{name: "Zebra"}),
        item(%{name: "Apple"}),
        item(%{name: "Mango"})
      ]

      result = LibraryHelpers.sorted_by(entries, :alpha)
      assert Enum.map(result, & &1.name) == ["Apple", "Mango", "Zebra"]
    end

    test "sorts by date_published descending for :year" do
      entries = [
        item(%{name: "2020", date_published: ~D[2020-01-01]}),
        item(%{name: "2023", date_published: ~D[2023-05-15]}),
        item(%{name: "2018", date_published: ~D[2018-12-25]})
      ]

      result = LibraryHelpers.sorted_by(entries, :year)
      assert Enum.map(result, & &1.name) == ["2023", "2020", "2018"]
    end

    test "returns entries in input order for :recent (Browse projection is pre-ordered)" do
      a = item(%{name: "Newest", rank: 0})
      b = item(%{name: "Middle", rank: 1})
      c = item(%{name: "Oldest", rank: 2})

      # `:recent` is the projection's implicit order; the helper is a no-op.
      assert LibraryHelpers.sorted_by([a, b, c], :recent) == [a, b, c]
    end
  end

  # --- sorted_by_last_watched/2 ---

  describe "sorted_by_last_watched/2" do
    test "sorts by progress.last_watched_at descending; entries without a summary go last" do
      a = item(%{id: "a", name: "Mid"})
      b = item(%{id: "b", name: "Newest"})
      c = item(%{id: "c", name: "No-progress"})

      progress_by_id = %{
        "a" => %{last_watched_at: ~U[2026-01-15 00:00:00Z]},
        "b" => %{last_watched_at: ~U[2026-02-01 00:00:00Z]}
      }

      result = LibraryHelpers.sorted_by_last_watched([a, b, c], progress_by_id)
      assert Enum.map(result, & &1.name) == ["Newest", "Mid", "No-progress"]
    end
  end

  # --- tab_counts/1 ---

  describe "tab_counts/1" do
    test "counts entries by kind bucket" do
      entries = [
        item(%{kind: :movie}),
        item(%{kind: :movie}),
        item(%{kind: :tv_series}),
        item(%{kind: :movie_series}),
        item(%{kind: :video_object})
      ]

      assert LibraryHelpers.tab_counts(entries) == %{all: 5, movies: 4, tv: 1}
    end

    test "returns zeros for empty list" do
      assert LibraryHelpers.tab_counts([]) == %{all: 0, movies: 0, tv: 0}
    end
  end

  # --- compute_progress_fraction/1 ---

  describe "compute_progress_fraction/1" do
    test "returns 0 for nil" do
      assert LibraryProgress.compute_progress_fraction(nil) == 0
    end

    test "computes percentage from position and duration" do
      progress = %{episode_position_seconds: 300.0, episode_duration_seconds: 600.0}
      assert LibraryProgress.compute_progress_fraction(progress) == 50.0
    end

    test "returns 0 when duration is zero" do
      progress = %{episode_position_seconds: 100.0, episode_duration_seconds: 0}
      assert LibraryProgress.compute_progress_fraction(progress) == 0
    end

    test "rounds to one decimal place" do
      progress = %{episode_position_seconds: 1.0, episode_duration_seconds: 3.0}
      assert LibraryProgress.compute_progress_fraction(progress) == 33.3
    end
  end

  # --- format_human_duration/1 ---

  describe "format_human_duration/1" do
    test "formats hours and minutes" do
      assert LibraryFormatters.format_human_duration(5400) == "1h 30m"
    end

    test "formats hours only when no remaining minutes" do
      assert LibraryFormatters.format_human_duration(7200) == "2h"
    end

    test "formats minutes only" do
      assert LibraryFormatters.format_human_duration(300) == "5m"
    end

    test "returns under 1 minute for small values" do
      assert LibraryFormatters.format_human_duration(30) == "< 1m"
    end
  end

  # --- format_resume_parts/2 ---

  describe "format_resume_parts/2" do
    defp entry(entity_overrides, progress_records \\ []) do
      entity = build_entity(entity_overrides)

      summary =
        case progress_records do
          [] -> nil
          _ -> %{episodes_completed: 0, episodes_total: 0}
        end

      %{entity: entity, progress: summary, progress_records: progress_records}
    end

    test "returns nils for nil resume" do
      assert LibraryProgress.format_resume_parts(nil, entry(%{})) == {nil, nil}
    end

    test "resume with season/episode returns label and time remaining" do
      resume = %{
        "action" => "resume",
        "seasonNumber" => 2,
        "episodeNumber" => 5,
        "positionSeconds" => 1200,
        "durationSeconds" => 3600
      }

      {label, time_remaining} = LibraryProgress.format_resume_parts(resume, entry(%{}))

      assert label == "Season 2 episode 5"
      assert time_remaining == "40m remaining"
    end

    test "resume without season falls back to episodes remaining" do
      episode = build_episode(%{episode_number: 1, content_url: "/ep1.mkv"})
      season = build_season(%{season_number: 1, episodes: [episode]})
      entity = build_entity(%{type: :tv_series, seasons: [season]})
      tv_entry = %{entity: entity, progress: nil, progress_records: []}

      resume = %{"action" => "resume", "positionSeconds" => 100, "durationSeconds" => 0}

      {label, time_remaining} = LibraryProgress.format_resume_parts(resume, tv_entry)

      assert label == nil
      assert time_remaining == "1 episode remaining"
    end

    test "begin with season/episode returns play label" do
      resume = %{"action" => "begin", "seasonNumber" => 1, "episodeNumber" => 1}
      {label, _} = LibraryProgress.format_resume_parts(resume, entry(%{}))

      assert label == "Play season 1 episode 1"
    end

    test "begin without season returns Play" do
      resume = %{"action" => "begin"}
      {label, _} = LibraryProgress.format_resume_parts(resume, entry(%{}))

      assert label == "Play"
    end

    test "unknown action returns nils" do
      assert LibraryProgress.format_resume_parts(%{"action" => "other"}, entry(%{})) == {nil, nil}
    end
  end

  # --- episodes_remaining_label/2 ---

  describe "episodes_remaining_label/2" do
    test "returns plural label for multiple remaining" do
      episode1 = build_episode(%{episode_number: 1, content_url: "/ep1.mkv"})
      episode2 = build_episode(%{episode_number: 2, content_url: "/ep2.mkv"})
      episode3 = build_episode(%{episode_number: 3, content_url: "/ep3.mkv"})
      season = build_season(%{season_number: 1, episodes: [episode1, episode2, episode3]})
      entity = build_entity(%{type: :tv_series, seasons: [season]})

      progress_records = [build_progress(%{season_number: 1, episode_number: 1, completed: true})]

      assert LibraryProgress.episodes_remaining_label(entity, progress_records) ==
               "2 episodes remaining"
    end

    test "returns singular label for one remaining" do
      episode1 = build_episode(%{episode_number: 1, content_url: "/ep1.mkv"})
      episode2 = build_episode(%{episode_number: 2, content_url: "/ep2.mkv"})
      season = build_season(%{season_number: 1, episodes: [episode1, episode2]})
      entity = build_entity(%{type: :tv_series, seasons: [season]})

      progress_records = [build_progress(%{season_number: 1, episode_number: 1, completed: true})]

      assert LibraryProgress.episodes_remaining_label(entity, progress_records) ==
               "1 episode remaining"
    end

    test "returns nil when all completed" do
      episode = build_episode(%{episode_number: 1, content_url: "/ep1.mkv"})
      season = build_season(%{season_number: 1, episodes: [episode]})
      entity = build_entity(%{type: :tv_series, seasons: [season]})

      progress_records = [build_progress(%{season_number: 1, episode_number: 1, completed: true})]

      assert LibraryProgress.episodes_remaining_label(entity, progress_records) == nil
    end

    test "returns nil for non-series entity types" do
      entity = build_entity(%{type: :movie})
      assert LibraryProgress.episodes_remaining_label(entity, []) == nil
    end
  end

  # --- format_type/1 ---

  describe "format_type/1" do
    test "formats known types" do
      assert LibraryFormatters.format_type(:movie) == "Movie"
      assert LibraryFormatters.format_type(:movie_series) == "Movie Series"
      assert LibraryFormatters.format_type(:tv_series) == "TV Series"
      assert LibraryFormatters.format_type(:video_object) == "Video"
    end

    test "capitalizes unknown types" do
      assert LibraryFormatters.format_type(:documentary) == "Documentary"
    end
  end

  # --- extract_year/1 ---

  describe "extract_year/1" do
    test "extracts year from date string" do
      assert LibraryFormatters.extract_year("2024-01-15") == "2024"
    end

    test "returns empty string for nil" do
      assert LibraryFormatters.extract_year(nil) == ""
    end
  end

  # --- in_progress?/1 ---

  describe "in_progress?/1 (legacy entry-shape wrapper)" do
    test "returns false for nil progress" do
      refute LibraryProgress.in_progress?(%{progress: nil})
    end

    test "returns true when episodes remain" do
      assert LibraryProgress.in_progress?(%{
               progress: %{episodes_completed: 3, episodes_total: 10}
             })
    end

    test "returns false when all episodes completed" do
      refute LibraryProgress.in_progress?(%{
               progress: %{episodes_completed: 10, episodes_total: 10}
             })
    end
  end

  describe "in_progress_summary?/1 (Phase 3.1 BrowseItem path)" do
    test "false for nil summary" do
      refute LibraryProgress.in_progress_summary?(nil)
    end

    test "true when summary has remaining episodes" do
      assert LibraryProgress.in_progress_summary?(%{episodes_completed: 3, episodes_total: 10})
    end

    test "false when all completed" do
      refute LibraryProgress.in_progress_summary?(%{episodes_completed: 5, episodes_total: 5})
    end
  end

  # --- reload_strategy/1 ---

  describe "reload_strategy/1" do
    test "returns :reset when new_entries is non-empty" do
      assert LibraryHelpers.reload_strategy(%{
               new_entries: [:new_entry_a],
               changed_ids: MapSet.new([:new_entry_a])
             }) == :reset
    end

    test "returns :reset even when deletions are also present" do
      assert LibraryHelpers.reload_strategy(%{
               new_entries: [:new_entry],
               changed_ids: MapSet.new([:new_entry, :deleted_entry])
             }) == :reset
    end

    test "returns {:touch, ids} for pure deletions" do
      assert LibraryHelpers.reload_strategy(%{
               new_entries: [],
               changed_ids: MapSet.new([:deleted_entry])
             }) == {:touch, [:deleted_entry]}
    end

    test "returns {:touch, ids} for in-place updates" do
      assert {:touch, ids} =
               LibraryHelpers.reload_strategy(%{
                 new_entries: [],
                 changed_ids: MapSet.new([:updated_a, :updated_b])
               })

      assert Enum.sort(ids) == [:updated_a, :updated_b]
    end

    test "returns {:touch, []} for an empty change set" do
      assert LibraryHelpers.reload_strategy(%{
               new_entries: [],
               changed_ids: MapSet.new()
             }) == {:touch, []}
    end
  end

  # --- completion_percentage/1 ---

  describe "completion_percentage/1" do
    test "returns percentage rounded to 0 decimals when duration known" do
      assert LibraryProgress.completion_percentage(%{
               position_seconds: 300.0,
               duration_seconds: 1_000.0
             }) == "30%"
    end

    test "rounds up mid-fraction values" do
      assert LibraryProgress.completion_percentage(%{
               position_seconds: 755.0,
               duration_seconds: 1_000.0
             }) == "76%"
    end

    test "returns 'unknown' when duration is zero" do
      assert LibraryProgress.completion_percentage(%{
               position_seconds: 100.0,
               duration_seconds: 0.0
             }) == "unknown"
    end

    test "returns 'unknown' when duration is missing" do
      assert LibraryProgress.completion_percentage(%{position_seconds: 100.0}) == "unknown"
    end

    test "returns 'unknown' for non-progress shape" do
      assert LibraryProgress.completion_percentage(nil) == "unknown"
      assert LibraryProgress.completion_percentage(%{}) == "unknown"
    end
  end

  # --- resolve_progress_fk/4 ---

  describe "resolve_progress_fk/4 — tv_series" do
    test "returns {:episode_id, id} when season + episode exist" do
      episode = build_episode(%{id: "ep-42", episode_number: 3, content_url: "/s1e3.mkv"})
      season = build_season(%{season_number: 2, episodes: [episode]})
      entity = %{type: :tv_series, seasons: [season]}
      entries = %{"entity-1" => %{entity: entity}}

      assert LibraryProgress.resolve_progress_fk(entries, "entity-1", 2, 3) ==
               {:episode_id, "ep-42"}
    end

    test "returns {:episode_id, nil} when season missing" do
      entity = %{type: :tv_series, seasons: [build_season(%{season_number: 1, episodes: []})]}
      entries = %{"entity-1" => %{entity: entity}}

      assert LibraryProgress.resolve_progress_fk(entries, "entity-1", 9, 1) == {:episode_id, nil}
    end

    test "returns {:episode_id, nil} when episode missing from season" do
      episode = build_episode(%{episode_number: 1, content_url: "/s1e1.mkv"})
      season = build_season(%{season_number: 1, episodes: [episode]})
      entity = %{type: :tv_series, seasons: [season]}
      entries = %{"entity-1" => %{entity: entity}}

      assert LibraryProgress.resolve_progress_fk(entries, "entity-1", 1, 99) == {:episode_id, nil}
    end

    test "returns {:episode_id, nil} when entity not in cache" do
      assert LibraryProgress.resolve_progress_fk(%{}, "missing", 1, 1) == {:episode_id, nil}
    end
  end

  describe "resolve_progress_fk/4 — movie_series (season == 0)" do
    test "returns {:movie_id, id} for movies with content_url at given ordinal" do
      movie1 = build_movie(%{id: "m-1", content_url: "/a.mkv"})
      movie2 = build_movie(%{id: "m-2", content_url: "/b.mkv"})
      entity = %{type: :movie_series, movies: [movie1, movie2]}
      entries = %{"entity-1" => %{entity: entity}}

      assert LibraryProgress.resolve_progress_fk(entries, "entity-1", 0, 1) ==
               {:movie_id, "m-1"}

      assert LibraryProgress.resolve_progress_fk(entries, "entity-1", 0, 2) ==
               {:movie_id, "m-2"}
    end

    test "skips movies without content_url when numbering ordinals" do
      absent = build_movie(%{id: "absent", content_url: nil})
      present = build_movie(%{id: "present", content_url: "/p.mkv"})
      entity = %{type: :movie_series, movies: [absent, present]}
      entries = %{"entity-1" => %{entity: entity}}

      assert LibraryProgress.resolve_progress_fk(entries, "entity-1", 0, 1) ==
               {:movie_id, "present"}
    end

    test "returns {:movie_id, nil} when ordinal out of range" do
      movie = build_movie(%{id: "m-1", content_url: "/a.mkv"})
      entity = %{type: :movie_series, movies: [movie]}
      entries = %{"entity-1" => %{entity: entity}}

      assert LibraryProgress.resolve_progress_fk(entries, "entity-1", 0, 99) == {:movie_id, nil}
    end
  end

  describe "resolve_progress_fk/4 — standalone movie (season == 0)" do
    test "returns {:movie_id, entity_id} for type :movie" do
      entity = %{type: :movie, id: "entity-42"}
      entries = %{"entity-42" => %{entity: entity}}

      assert LibraryProgress.resolve_progress_fk(entries, "entity-42", 0, 1) ==
               {:movie_id, "entity-42"}
    end
  end

  describe "resolve_progress_fk/4 — fallback" do
    test "returns {:movie_id, entity_id} when entity missing from cache (season 0)" do
      assert LibraryProgress.resolve_progress_fk(%{}, "unknown", 0, 1) == {:movie_id, "unknown"}
    end
  end

  # --- offline_summary/2 ---

  describe "offline_summary/2" do
    test "returns nil when every dir is :watching" do
      assert LibraryAvailability.offline_summary(%{"/mnt/a" => :watching}, 0) == nil
      assert LibraryAvailability.offline_summary(%{}, 0) == nil
    end

    test "returns nil when dirs are :initializing (not yet unavailable)" do
      assert LibraryAvailability.offline_summary(%{"/mnt/a" => :initializing}, 0) == nil
    end

    test "single-dir offline, pluralises items correctly" do
      status = %{"/mnt/videos" => :unavailable}

      assert LibraryAvailability.offline_summary(status, 1) ==
               "/mnt/videos is offline — 1 item temporarily unavailable."

      assert LibraryAvailability.offline_summary(status, 23) ==
               "/mnt/videos is offline — 23 items temporarily unavailable."
    end

    test "multiple dirs offline mentions the count instead of naming each" do
      status = %{
        "/mnt/videos" => :unavailable,
        "/mnt/nas/media" => :unavailable,
        "/mnt/extra" => :watching
      }

      assert LibraryAvailability.offline_summary(status, 41) ==
               "2 storage locations offline — 41 items temporarily unavailable."
    end

    test "zero items edge case (dir offline but nothing indexed from it yet)" do
      status = %{"/mnt/videos" => :unavailable}

      assert LibraryAvailability.offline_summary(status, 0) ==
               "/mnt/videos is offline — 0 items temporarily unavailable."
    end
  end

  describe "playback_failed_flash/1" do
    test "episode with season and episode numbers includes S0xE0y" do
      payload = %{
        message: "Failed to recognize file format.",
        entity_name: "Sample Show",
        season_number: 3,
        episode_number: 5,
        episode_name: "One Day",
        content_url: "/mnt/tv/Sample Show/Sample.Show.S03E05.mkv"
      }

      assert LibraryFormatters.playback_failed_flash(payload) ==
               "Couldn't play Sample Show S3E5 — Failed to recognize file format."
    end

    test "movie without season/episode falls back to entity name only" do
      payload = %{
        message: "Error opening input file",
        entity_name: "Sample Movie",
        season_number: nil,
        episode_number: nil,
        episode_name: nil,
        content_url: "/mnt/movies/Sample.Movie.mkv"
      }

      assert LibraryFormatters.playback_failed_flash(payload) ==
               "Couldn't play Sample Movie — Error opening input file."
    end

    test "unknown entity name uses filename" do
      payload = %{
        message: "Cannot open file",
        entity_name: nil,
        season_number: nil,
        episode_number: nil,
        episode_name: nil,
        content_url: "/mnt/tv/Something.S01E01.mkv"
      }

      assert LibraryFormatters.playback_failed_flash(payload) ==
               "Couldn't play Something.S01E01.mkv — Cannot open file."
    end

    test "preserves exclamation mark in terminal punctuation" do
      payload = %{
        message: "Nope!",
        entity_name: "Show",
        season_number: 1,
        episode_number: 2,
        episode_name: nil,
        content_url: "/x.mkv"
      }

      assert LibraryFormatters.playback_failed_flash(payload) ==
               "Couldn't play Show S1E2 — Nope!"
    end

    test "hints about storage when message looks like a missing-file error" do
      payload = %{
        message: "Error opening input: No such file or directory",
        entity_name: "Show",
        season_number: 2,
        episode_number: 3,
        episode_name: nil,
        content_url: "/mnt/tv/Show.S02E03.mkv"
      }

      flash = LibraryFormatters.playback_failed_flash(payload)

      assert flash =~ "Couldn't play Show S2E3"
      assert flash =~ "drive is mounted"
    end
  end
end
