defmodule MediaCentaurWeb.LibraryHelpersTest do
  use ExUnit.Case, async: true

  import MediaCentaur.TestFactory

  alias MediaCentaurWeb.LibraryHelpers

  # --- Helpers ---

  defp entry(entity_overrides, progress_records \\ []) do
    entity = build_entity(entity_overrides)

    summary =
      case progress_records do
        [] -> nil
        _ -> %{episodes_completed: 0, episodes_total: 0}
      end

    %{entity: entity, progress: summary, progress_records: progress_records}
  end

  # --- filtered_by_tab/2 ---

  describe "filtered_by_tab/2" do
    test "returns all entries for :all" do
      entries = [entry(%{type: :movie}), entry(%{type: :tv_series})]
      assert LibraryHelpers.filtered_by_tab(entries, :all) == entries
    end

    test "filters to movies and video objects for :movies" do
      movie = entry(%{type: :movie, name: "A"})
      series = entry(%{type: :movie_series, name: "B"})
      video = entry(%{type: :video_object, name: "C"})
      tv = entry(%{type: :tv_series, name: "D"})

      result = LibraryHelpers.filtered_by_tab([movie, series, video, tv], :movies)
      names = Enum.map(result, & &1.entity.name)

      assert names == ["A", "B", "C"]
    end

    test "filters to tv_series for :tv" do
      movie = entry(%{type: :movie, name: "A"})
      tv = entry(%{type: :tv_series, name: "B"})

      result = LibraryHelpers.filtered_by_tab([movie, tv], :tv)
      assert length(result) == 1
      assert hd(result).entity.name == "B"
    end
  end

  # --- filtered_by_text/2 ---

  describe "filtered_by_text/2" do
    test "returns all entries for empty string" do
      entries = [entry(%{name: "Anything"})]
      assert LibraryHelpers.filtered_by_text(entries, "") == entries
    end

    test "matches entity name case-insensitively" do
      match = entry(%{name: "Sample Show Eight"})
      miss = entry(%{name: "Sample Show"})

      result = LibraryHelpers.filtered_by_text([match, miss], "breaking")
      assert length(result) == 1
      assert hd(result).entity.name == "Sample Show Eight"
    end

    test "matches nested episode names for tv_series" do
      episode = build_episode(%{name: "Ozymandias"})
      season = build_season(%{episodes: [episode]})
      entity = build_entity(%{type: :tv_series, name: "Sample Show Eight", seasons: [season]})
      tv_entry = %{entity: entity, progress: nil, progress_records: []}

      other = entry(%{name: "Sample Show"})

      result = LibraryHelpers.filtered_by_text([tv_entry, other], "ozyma")
      assert length(result) == 1
      assert hd(result).entity.name == "Sample Show Eight"
    end

    test "matches nested movie names for movie_series" do
      movie = build_movie(%{name: "The Two Towers"})
      entity = build_entity(%{type: :movie_series, name: "Lord of the Rings", movies: [movie]})
      series_entry = %{entity: entity, progress: nil, progress_records: []}

      other = entry(%{name: "Star Wars"})

      result = LibraryHelpers.filtered_by_text([series_entry, other], "two towers")
      assert length(result) == 1
      assert hd(result).entity.name == "Lord of the Rings"
    end

    test "returns empty list when nothing matches" do
      entries = [entry(%{name: "Sample Show Eight"})]
      assert LibraryHelpers.filtered_by_text(entries, "sopranos") == []
    end
  end

  # --- sorted_by/2 ---

  describe "sorted_by/2" do
    test "sorts alphabetically by name" do
      entries = [entry(%{name: "Zebra"}), entry(%{name: "Apple"}), entry(%{name: "Mango"})]
      result = LibraryHelpers.sorted_by(entries, :alpha)
      names = Enum.map(result, & &1.entity.name)

      assert names == ["Apple", "Mango", "Zebra"]
    end

    test "sorts by year descending" do
      entries = [
        entry(%{date_published: "2020-01-01"}),
        entry(%{date_published: "2023-05-15"}),
        entry(%{date_published: "2018-12-25"})
      ]

      result = LibraryHelpers.sorted_by(entries, :year)
      years = Enum.map(result, & &1.entity.date_published)

      assert years == ["2023-05-15", "2020-01-01", "2018-12-25"]
    end

    test "sorts by inserted_at descending for :recent" do
      old = DateTime.new!(~D[2025-01-01], ~T[00:00:00], "Etc/UTC")
      new = DateTime.new!(~D[2026-03-15], ~T[12:00:00], "Etc/UTC")

      entries = [
        entry(%{name: "Old", inserted_at: old}),
        entry(%{name: "New", inserted_at: new})
      ]

      result = LibraryHelpers.sorted_by(entries, :recent)
      names = Enum.map(result, & &1.entity.name)

      assert names == ["New", "Old"]
    end
  end

  # --- tab_counts/1 ---

  describe "tab_counts/1" do
    test "counts entries by type bucket" do
      entries = [
        entry(%{type: :movie}),
        entry(%{type: :movie}),
        entry(%{type: :tv_series}),
        entry(%{type: :movie_series}),
        entry(%{type: :video_object})
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
      assert LibraryHelpers.compute_progress_fraction(nil) == 0
    end

    test "computes percentage from position and duration" do
      progress = %{episode_position_seconds: 300.0, episode_duration_seconds: 600.0}
      assert LibraryHelpers.compute_progress_fraction(progress) == 50.0
    end

    test "returns 0 when duration is zero" do
      progress = %{episode_position_seconds: 100.0, episode_duration_seconds: 0}
      assert LibraryHelpers.compute_progress_fraction(progress) == 0
    end

    test "rounds to one decimal place" do
      progress = %{episode_position_seconds: 1.0, episode_duration_seconds: 3.0}
      assert LibraryHelpers.compute_progress_fraction(progress) == 33.3
    end
  end

  # --- format_human_duration/1 ---

  describe "format_human_duration/1" do
    test "formats hours and minutes" do
      assert LibraryHelpers.format_human_duration(5400) == "1h 30m"
    end

    test "formats hours only when no remaining minutes" do
      assert LibraryHelpers.format_human_duration(7200) == "2h"
    end

    test "formats minutes only" do
      assert LibraryHelpers.format_human_duration(300) == "5m"
    end

    test "returns under 1 minute for small values" do
      assert LibraryHelpers.format_human_duration(30) == "< 1m"
    end
  end

  # --- format_resume_parts/2 ---

  describe "format_resume_parts/2" do
    test "returns nils for nil resume" do
      assert LibraryHelpers.format_resume_parts(nil, entry(%{})) == {nil, nil}
    end

    test "resume with season/episode returns label and time remaining" do
      resume = %{
        "action" => "resume",
        "seasonNumber" => 2,
        "episodeNumber" => 5,
        "positionSeconds" => 1200,
        "durationSeconds" => 3600
      }

      {label, time_remaining} = LibraryHelpers.format_resume_parts(resume, entry(%{}))

      assert label == "Season 2 episode 5"
      assert time_remaining == "40m remaining"
    end

    test "resume without season falls back to episodes remaining" do
      episode = build_episode(%{episode_number: 1, content_url: "/ep1.mkv"})
      season = build_season(%{season_number: 1, episodes: [episode]})
      entity = build_entity(%{type: :tv_series, seasons: [season]})
      tv_entry = %{entity: entity, progress: nil, progress_records: []}

      resume = %{"action" => "resume", "positionSeconds" => 100, "durationSeconds" => 0}

      {label, time_remaining} = LibraryHelpers.format_resume_parts(resume, tv_entry)

      assert label == nil
      assert time_remaining == "1 episode remaining"
    end

    test "begin with season/episode returns play label" do
      resume = %{"action" => "begin", "seasonNumber" => 1, "episodeNumber" => 1}
      {label, _} = LibraryHelpers.format_resume_parts(resume, entry(%{}))

      assert label == "Play season 1 episode 1"
    end

    test "begin without season returns Play" do
      resume = %{"action" => "begin"}
      {label, _} = LibraryHelpers.format_resume_parts(resume, entry(%{}))

      assert label == "Play"
    end

    test "unknown action returns nils" do
      assert LibraryHelpers.format_resume_parts(%{"action" => "other"}, entry(%{})) == {nil, nil}
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

      assert LibraryHelpers.episodes_remaining_label(entity, progress_records) ==
               "2 episodes remaining"
    end

    test "returns singular label for one remaining" do
      episode1 = build_episode(%{episode_number: 1, content_url: "/ep1.mkv"})
      episode2 = build_episode(%{episode_number: 2, content_url: "/ep2.mkv"})
      season = build_season(%{season_number: 1, episodes: [episode1, episode2]})
      entity = build_entity(%{type: :tv_series, seasons: [season]})

      progress_records = [build_progress(%{season_number: 1, episode_number: 1, completed: true})]

      assert LibraryHelpers.episodes_remaining_label(entity, progress_records) ==
               "1 episode remaining"
    end

    test "returns nil when all completed" do
      episode = build_episode(%{episode_number: 1, content_url: "/ep1.mkv"})
      season = build_season(%{season_number: 1, episodes: [episode]})
      entity = build_entity(%{type: :tv_series, seasons: [season]})

      progress_records = [build_progress(%{season_number: 1, episode_number: 1, completed: true})]

      assert LibraryHelpers.episodes_remaining_label(entity, progress_records) == nil
    end

    test "returns nil for non-series entity types" do
      entity = build_entity(%{type: :movie})
      assert LibraryHelpers.episodes_remaining_label(entity, []) == nil
    end
  end

  # --- format_type/1 ---

  describe "format_type/1" do
    test "formats known types" do
      assert LibraryHelpers.format_type(:movie) == "Movie"
      assert LibraryHelpers.format_type(:movie_series) == "Movie Series"
      assert LibraryHelpers.format_type(:tv_series) == "TV Series"
      assert LibraryHelpers.format_type(:video_object) == "Video"
    end

    test "capitalizes unknown types" do
      assert LibraryHelpers.format_type(:documentary) == "Documentary"
    end
  end

  # --- extract_year/1 ---

  describe "extract_year/1" do
    test "extracts year from date string" do
      assert LibraryHelpers.extract_year("2024-01-15") == "2024"
    end

    test "returns empty string for nil" do
      assert LibraryHelpers.extract_year(nil) == ""
    end
  end

  # --- merge_progress_record/2 ---

  describe "merge_progress_record/2" do
    test "returns records unchanged for nil change" do
      records = [build_progress(%{episode_id: "ep-1"})]
      assert LibraryHelpers.merge_progress_record(records, nil) == records
    end

    test "replaces an existing episode record by episode_id" do
      existing = build_progress(%{episode_id: "ep-1", completed: false})
      updated = build_progress(%{episode_id: "ep-1", completed: true})

      result = LibraryHelpers.merge_progress_record([existing], updated)

      assert length(result) == 1
      assert hd(result).completed == true
    end

    test "replaces an existing movie record by movie_id" do
      existing = build_progress(%{movie_id: "movie-1", completed: false})
      updated = build_progress(%{movie_id: "movie-1", completed: true})

      result = LibraryHelpers.merge_progress_record([existing], updated)

      assert length(result) == 1
      assert hd(result).completed == true
    end

    test "replaces an existing video object record by video_object_id" do
      existing = build_progress(%{video_object_id: "vo-1", completed: false})
      updated = build_progress(%{video_object_id: "vo-1", completed: true})

      result = LibraryHelpers.merge_progress_record([existing], updated)

      assert length(result) == 1
      assert hd(result).completed == true
    end

    test "appends a new record that does not match any existing FK" do
      record1 = build_progress(%{episode_id: "ep-1"})
      new_record = build_progress(%{episode_id: "ep-2"})

      result = LibraryHelpers.merge_progress_record([record1], new_record)

      assert length(result) == 2
      assert Enum.any?(result, &(&1.episode_id == "ep-1"))
      assert Enum.any?(result, &(&1.episode_id == "ep-2"))
    end

    test "prepends first record into an empty list" do
      new_record = build_progress(%{episode_id: "ep-1"})

      assert LibraryHelpers.merge_progress_record([], new_record) == [new_record]
    end
  end

  # --- max_last_watched_at/1 ---

  describe "max_last_watched_at/1" do
    test "returns nil when progress_records is empty" do
      assert LibraryHelpers.max_last_watched_at(%{progress_records: []}) == nil
    end

    test "returns the timestamp of the only record" do
      timestamp = ~U[2026-01-15 12:00:00Z]
      record = build_progress(%{episode_id: "ep-1", last_watched_at: timestamp})

      assert LibraryHelpers.max_last_watched_at(%{progress_records: [record]}) == timestamp
    end

    test "returns the most recent timestamp across records" do
      older = build_progress(%{episode_id: "ep-1", last_watched_at: ~U[2026-01-01 00:00:00Z]})
      newer = build_progress(%{episode_id: "ep-2", last_watched_at: ~U[2026-02-01 00:00:00Z]})
      middle = build_progress(%{episode_id: "ep-3", last_watched_at: ~U[2026-01-15 00:00:00Z]})

      result = LibraryHelpers.max_last_watched_at(%{progress_records: [older, newer, middle]})

      assert result == ~U[2026-02-01 00:00:00Z]
    end
  end

  # --- merge_extra_progress/2 ---

  describe "merge_extra_progress/2" do
    test "returns records unchanged for nil change" do
      records = [%{extra_id: "a", completed: false}]
      assert LibraryHelpers.merge_extra_progress(records, nil) == records
    end

    test "replaces existing record by extra_id" do
      existing = %{extra_id: "a", completed: false}
      updated = %{extra_id: "a", completed: true}

      result = LibraryHelpers.merge_extra_progress([existing], updated)

      assert length(result) == 1
      assert hd(result).completed == true
    end

    test "prepends new record when not found" do
      existing = %{extra_id: "a", completed: false}
      new_record = %{extra_id: "b", completed: true}

      result = LibraryHelpers.merge_extra_progress([existing], new_record)

      assert length(result) == 2
      assert hd(result).extra_id == "b"
    end
  end

  # --- in_progress?/1 ---

  describe "in_progress?/1" do
    test "returns false for nil progress" do
      refute LibraryHelpers.in_progress?(%{progress: nil})
    end

    test "returns true when episodes remain" do
      assert LibraryHelpers.in_progress?(%{
               progress: %{episodes_completed: 3, episodes_total: 10}
             })
    end

    test "returns false when all episodes completed" do
      refute LibraryHelpers.in_progress?(%{
               progress: %{episodes_completed: 10, episodes_total: 10}
             })
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
      # Mixed additions + deletions still reset — the addition is the
      # condition that forces the reset, regardless of what else happened.
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
end
