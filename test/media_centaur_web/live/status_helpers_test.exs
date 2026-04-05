defmodule MediaCentaurWeb.StatusHelpersTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.StatusHelpers

  # --- derive_playback/1 ---

  describe "derive_playback/1" do
    test "returns idle for empty sessions" do
      assert StatusHelpers.derive_playback(%{}) == %{
               state: :idle,
               now_playing: nil,
               sessions: %{}
             }
    end

    test "picks playing session over paused" do
      sessions = %{
        "a" => %{state: :paused, now_playing: %{title: "Paused"}},
        "b" => %{state: :playing, now_playing: %{title: "Playing"}}
      }

      result = StatusHelpers.derive_playback(sessions)
      assert result.state == :playing
      assert result.now_playing == %{title: "Playing"}
    end

    test "returns single session when only one exists" do
      sessions = %{
        "a" => %{state: :paused, now_playing: %{title: "Solo"}}
      }

      result = StatusHelpers.derive_playback(sessions)
      assert result.state == :paused
    end
  end

  # --- format_remaining/1 ---

  describe "format_remaining/1" do
    test "returns finished for zero or negative" do
      assert StatusHelpers.format_remaining(0) == "finished"
      assert StatusHelpers.format_remaining(-5) == "finished"
    end

    test "sub-minute durations collapse to '< 1m remaining' (UIDR-004 forbids seconds)" do
      assert StatusHelpers.format_remaining(45) == "< 1m remaining"
      assert StatusHelpers.format_remaining(1) == "< 1m remaining"
      assert StatusHelpers.format_remaining(59) == "< 1m remaining"
    end

    test "formats minutes in UIDR-004 shape" do
      assert StatusHelpers.format_remaining(180) == "3m remaining"
      assert StatusHelpers.format_remaining(60) == "1m remaining"
    end

    test "formats hours and minutes in UIDR-004 shape" do
      assert StatusHelpers.format_remaining(3600) == "1h remaining"
      assert StatusHelpers.format_remaining(7200) == "2h remaining"
      assert StatusHelpers.format_remaining(5400) == "1h 30m remaining"
      assert StatusHelpers.format_remaining(12_900) == "3h 35m remaining"
    end
  end

  # --- format_throughput/1 ---

  describe "format_throughput/1" do
    test "returns dash for zero" do
      assert StatusHelpers.format_throughput(0.0) == "—"
    end

    test "formats rate with /s suffix" do
      assert StatusHelpers.format_throughput(2.5) == "2.5/s"
    end
  end

  # --- format_duration/1 ---

  describe "format_duration/1" do
    test "returns dash for nil" do
      assert StatusHelpers.format_duration(nil) == "—"
    end

    test "formats milliseconds" do
      assert StatusHelpers.format_duration(500) == "500ms"
    end

    test "formats seconds" do
      assert StatusHelpers.format_duration(2500) == "2.5s"
    end

    test "formats minutes" do
      assert StatusHelpers.format_duration(120_000) == "2.0m"
    end
  end

  # --- format_datetime/1 ---

  describe "format_datetime/1" do
    test "returns dash for nil" do
      assert StatusHelpers.format_datetime(nil) == "—"
    end

    test "formats datetime" do
      datetime = DateTime.new!(~D[2026-03-15], ~T[14:30:00], "Etc/UTC")
      assert StatusHelpers.format_datetime(datetime) == "2026-03-15 14:30"
    end
  end

  # --- format_bytes/1 ---

  describe "format_bytes/1" do
    test "formats terabytes" do
      tib = Float.pow(1024.0, 4)
      assert StatusHelpers.format_bytes(2.5 * tib) == "2.5 TiB"
    end

    test "formats gigabytes" do
      gib = Float.pow(1024.0, 3)
      assert StatusHelpers.format_bytes(100.0 * gib) == "100.0 GiB"
    end
  end

  # --- stage display ---

  describe "stage_dot_class/1" do
    test "maps stage status to dot class" do
      assert StatusHelpers.stage_dot_class(:idle) == "bg-base-content/20"
      assert StatusHelpers.stage_dot_class(:active) == "bg-success"
      assert StatusHelpers.stage_dot_class(:saturated) == "bg-warning"
      assert StatusHelpers.stage_dot_class(:erroring) == "bg-error"
    end
  end

  describe "stage_text_class/1" do
    test "maps stage status to text class" do
      assert StatusHelpers.stage_text_class(:idle) == "text-base-content/60"
      assert StatusHelpers.stage_text_class(:active) == "text-success"
    end
  end

  describe "stage_status_label/1" do
    test "maps status to label" do
      assert StatusHelpers.stage_status_label(:idle) == "idle"
      assert StatusHelpers.stage_status_label(:active) == "active"
      assert StatusHelpers.stage_status_label(:saturated) == "saturated"
      assert StatusHelpers.stage_status_label(:erroring) == "erroring"
    end
  end

  describe "stage_display_name/1" do
    test "maps stage atom to display name" do
      assert StatusHelpers.stage_display_name(:parse) == "Parse Media Path"
      assert StatusHelpers.stage_display_name(:search) == "Match on TMDB"
      assert StatusHelpers.stage_display_name(:fetch_metadata) == "Enrich Metadata"
      assert StatusHelpers.stage_display_name(:ingest) == "Add to Library"
    end
  end

  # --- directory status ---

  describe "resolve_dir_status/2" do
    test "returns :missing when dir does not exist" do
      health = %{dir: "/missing", dir_exists: false}
      assert StatusHelpers.resolve_dir_status(health, []) == :missing
    end

    test "returns watcher state when found" do
      health = %{dir: "/media", dir_exists: true}
      watchers = [%{dir: "/media", state: :watching}]

      assert StatusHelpers.resolve_dir_status(health, watchers) == :watching
    end

    test "returns :stopped when dir exists but no watcher" do
      health = %{dir: "/media", dir_exists: true}
      assert StatusHelpers.resolve_dir_status(health, []) == :stopped
    end
  end

  describe "dir_status_label/1" do
    test "maps status to label" do
      assert StatusHelpers.dir_status_label(:missing) == "missing"
      assert StatusHelpers.dir_status_label(:stopped) == "not watched"
      assert StatusHelpers.dir_status_label(:watching) == "watching"
      assert StatusHelpers.dir_status_label(:initializing) == "initializing"
      assert StatusHelpers.dir_status_label(:unknown) == "unavailable"
    end
  end

  describe "dir_status_text_class/1" do
    test "maps status to text class" do
      assert StatusHelpers.dir_status_text_class(:missing) == "text-error"
      assert StatusHelpers.dir_status_text_class(:watching) == "text-success"
      assert StatusHelpers.dir_status_text_class(:stopped) == "text-warning"
    end
  end

  # --- playback display ---

  describe "playback_text_class/1" do
    test "maps playback state to text class" do
      assert StatusHelpers.playback_text_class(:idle) == "text-base-content/60"
      assert StatusHelpers.playback_text_class(:playing) == "text-success"
      assert StatusHelpers.playback_text_class(:paused) == "text-warning"
      assert StatusHelpers.playback_text_class(:other) == "text-info"
    end
  end

  describe "playback_progress_class/1" do
    test "maps playback state to progress class" do
      assert StatusHelpers.playback_progress_class(:playing) == "progress-success"
      assert StatusHelpers.playback_progress_class(:paused) == "progress-warning"
      assert StatusHelpers.playback_progress_class(:idle) == "progress-info"
    end
  end

  describe "playback_border_class/1" do
    test "maps playback state to border class" do
      assert StatusHelpers.playback_border_class(:playing) == "border-success"
      assert StatusHelpers.playback_border_class(:paused) == "border-warning"
      assert StatusHelpers.playback_border_class(:idle) == "border-base-content/20"
    end
  end

  # --- usage display ---

  describe "usage_progress_class/1" do
    test "returns error for high usage" do
      assert StatusHelpers.usage_progress_class(95) == "progress-error"
    end

    test "returns warning for moderate usage" do
      assert StatusHelpers.usage_progress_class(80) == "progress-warning"
    end

    test "returns success for low usage" do
      assert StatusHelpers.usage_progress_class(50) == "progress-success"
    end
  end

  describe "usage_text_class/1" do
    test "returns error for high usage" do
      assert StatusHelpers.usage_text_class(92) == "text-error"
    end

    test "returns warning for moderate usage" do
      assert StatusHelpers.usage_text_class(78) == "text-warning"
    end

    test "returns success for low usage" do
      assert StatusHelpers.usage_text_class(60) == "text-success"
    end
  end

  # --- merge_recent_errors/2 ---

  describe "merge_recent_errors/2" do
    test "merges and sorts errors by updated_at descending" do
      now = DateTime.utc_now()
      old = DateTime.add(now, -3600, :second)

      content_stats = %{recent_errors: [%{message: "c1", updated_at: old}]}
      image_stats = %{recent_errors: [%{message: "i1", updated_at: now}]}

      result = StatusHelpers.merge_recent_errors(content_stats, image_stats)

      assert length(result) == 2
      assert hd(result).message == "i1"
    end

    test "limits to 50 entries" do
      errors = for i <- 1..30, do: %{message: "e#{i}", updated_at: DateTime.utc_now()}

      content_stats = %{recent_errors: errors}
      image_stats = %{recent_errors: errors}

      result = StatusHelpers.merge_recent_errors(content_stats, image_stats)
      assert length(result) == 50
    end
  end
end
