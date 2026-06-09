defmodule MediaCentaurWeb.StatusHelpersTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Library.WatchProgress
  alias MediaCentaurWeb.StatusHelpers

  # --- Library overview helpers ---

  describe "gap_count_class/1" do
    test "warns when the gap count is positive" do
      assert StatusHelpers.gap_count_class(1) == "text-warning"
      assert StatusHelpers.gap_count_class(42) == "text-warning"
    end

    test "is muted when there is no gap" do
      assert StatusHelpers.gap_count_class(0) == "text-base-content/40"
    end
  end

  describe "summarize_at_risk/4" do
    setup do
      %{now: ~U[2026-06-07 12:00:00Z], ttl_days: 30}
    end

    test "returns nil when nothing is at risk", %{now: now, ttl_days: ttl} do
      assert StatusHelpers.summarize_at_risk(%{}, %{}, now, ttl) == nil
    end

    test "ignores dirs that are currently available", %{now: now, ttl_days: ttl} do
      summary = %{"/media" => %{file_count: 5, earliest_absent_since: now}}
      dir_status = %{"/media" => :available}

      assert StatusHelpers.summarize_at_risk(summary, dir_status, now, ttl) == nil
    end

    test "aggregates file counts across offline dirs and reports the soonest purge",
         %{now: now, ttl_days: ttl} do
      summary = %{
        "/media/a" => %{file_count: 3, earliest_absent_since: DateTime.add(now, -25, :day)},
        "/media/b" => %{file_count: 2, earliest_absent_since: DateTime.add(now, -10, :day)}
      }

      dir_status = %{"/media/a" => :unavailable, "/media/b" => :unavailable}

      result = StatusHelpers.summarize_at_risk(summary, dir_status, now, ttl)

      assert result.file_count == 5
      # /media/a is older (25 days) so it purges soonest: 30 - 25 = 5 days
      assert result.purge_in_days == 5
    end

    test "treats unknown dir status as offline", %{now: now, ttl_days: ttl} do
      summary = %{"/media" => %{file_count: 1, earliest_absent_since: now}}

      result = StatusHelpers.summarize_at_risk(summary, %{}, now, ttl)

      assert result.file_count == 1
    end
  end

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

  # --- progress_matches_session?/2 ---

  describe "progress_matches_session?/2" do
    # The synthesised `:playable_item` field carries the
    # `(container_type, container_id)` discriminator —
    # `MediaCentaur.Library.EntityShape.attach_container/3` plugs it on
    # at extraction time. These tests construct the same shape directly
    # since they exercise the pure matcher in isolation.

    test "matches against now_playing.entity_id (real MpvSession.build_now_playing shape)" do
      # The session's `now_playing` map produced by
      # `MpvSession.build_now_playing/1` carries only `:entity_id` — no
      # legacy `:movie_id` / `:episode_id` / `:video_object_id` keys.
      # The matcher must work against that shape.
      movie_id = Ecto.UUID.generate()

      progress = %WatchProgress{
        playable_item: %{container_type: :movie, container_id: movie_id}
      }

      now_playing = %{entity_id: movie_id}

      assert StatusHelpers.progress_matches_session?(progress, now_playing)
    end

    test "matches movie progress to movie session" do
      progress = %WatchProgress{
        playable_item: %{container_type: :movie, container_id: "be868a6e"}
      }

      now_playing = %{entity_id: "be868a6e"}

      assert StatusHelpers.progress_matches_session?(progress, now_playing)
    end

    test "matches episode progress to episode session" do
      progress = %WatchProgress{
        playable_item: %{container_type: :episode, container_id: "ep-uuid"}
      }

      now_playing = %{entity_id: "ep-uuid"}

      assert StatusHelpers.progress_matches_session?(progress, now_playing)
    end

    test "matches video object progress to video object session" do
      progress = %WatchProgress{
        playable_item: %{container_type: :video_object, container_id: "vo-uuid"}
      }

      now_playing = %{entity_id: "vo-uuid"}

      assert StatusHelpers.progress_matches_session?(progress, now_playing)
    end

    test "does not match when container_id differs from session entity_id" do
      progress = %WatchProgress{
        playable_item: %{container_type: :movie, container_id: "be868a6e"}
      }

      now_playing = %{entity_id: "other-id"}

      refute StatusHelpers.progress_matches_session?(progress, now_playing)
    end

    test "does not match when playable_item is missing" do
      progress = %WatchProgress{playable_item: nil}
      now_playing = %{entity_id: "be868a6e"}

      refute StatusHelpers.progress_matches_session?(progress, now_playing)
    end
  end

  # --- format_at_risk_for_dir/3 ---

  describe "format_at_risk_for_dir/3" do
    # The status page only surfaces an at-risk warning for dirs the
    # user can do something about — i.e. dirs that are currently
    # offline, since those are the ones whose absence clock is ticking
    # without the user's awareness. An online dir's at-risk count is
    # accurate-but-uninteresting (the watcher will resolve it on its
    # next scan), so we deliberately suppress the row for those.

    test "returns nil when the dir has no absent files" do
      assert StatusHelpers.format_at_risk_for_dir(
               "/mnt/cold",
               %{},
               %{"/mnt/cold" => :unavailable},
               DateTime.utc_now(),
               30
             ) == nil
    end

    test "returns nil when the dir is currently :available (not user-actionable)" do
      summary = %{
        "/mnt/cold" => %{
          file_count: 5,
          earliest_absent_since: DateTime.add(DateTime.utc_now(), -20, :day)
        }
      }

      assert StatusHelpers.format_at_risk_for_dir(
               "/mnt/cold",
               summary,
               %{"/mnt/cold" => :available},
               DateTime.utc_now(),
               30
             ) == nil
    end

    test "returns a row when the dir is unavailable and has at-risk files" do
      now = ~U[2026-05-05 12:00:00Z]
      earliest = DateTime.add(now, -10, :day)

      summary = %{"/mnt/cold" => %{file_count: 12, earliest_absent_since: earliest}}
      dir_status = %{"/mnt/cold" => :unavailable}

      assert %{
               file_count: 12,
               earliest_absent_since: ^earliest,
               purge_in_days: 20
             } = StatusHelpers.format_at_risk_for_dir("/mnt/cold", summary, dir_status, now, 30)
    end

    test "purge_in_days is 0 when the file is already past the TTL" do
      now = ~U[2026-05-05 12:00:00Z]
      # Absent for 45 days — past the 30-day TTL.
      earliest = DateTime.add(now, -45, :day)

      summary = %{"/mnt/cold" => %{file_count: 1, earliest_absent_since: earliest}}
      dir_status = %{"/mnt/cold" => :unavailable}

      row = StatusHelpers.format_at_risk_for_dir("/mnt/cold", summary, dir_status, now, 30)
      assert row.purge_in_days == 0
    end

    test "treats a dir absent from the status map as unavailable (optimistic display)" do
      # If the dir flipped offline before Availability seeded its
      # cache, we'd rather show the at-risk warning than hide it.
      now = DateTime.utc_now()

      summary = %{
        "/mnt/orphan" => %{file_count: 3, earliest_absent_since: DateTime.add(now, -5, :day)}
      }

      assert %{file_count: 3} =
               StatusHelpers.format_at_risk_for_dir("/mnt/orphan", summary, %{}, now, 30)
    end
  end

  # --- Watcher activity narrative ---

  describe "dir_failure_reason_label/1" do
    test "explains a missing mount in plain language" do
      label = "drive not mounted — waiting for it to come back"
      assert StatusHelpers.dir_failure_reason_label(:unmounted) == label
      assert StatusHelpers.dir_failure_reason_label(:never_mounted) == label
    end

    test "names the inotify-tools gap" do
      assert StatusHelpers.dir_failure_reason_label(:inotify_missing) ==
               "inotify-tools not installed — live detection off"
    end

    test "covers backend-start and inaccessible causes" do
      assert StatusHelpers.dir_failure_reason_label(:backend_error) =~ "couldn't start"
      assert StatusHelpers.dir_failure_reason_label(:inaccessible) =~ "inaccessible"
    end

    test "falls back to a generic line for an unknown or nil reason" do
      assert StatusHelpers.dir_failure_reason_label(nil) =~ "not being watched"
      assert StatusHelpers.dir_failure_reason_label(:something_new) =~ "not being watched"
    end
  end

  describe "format_scan_counts/1" do
    test "groups thousands and pluralizes files" do
      assert StatusHelpers.format_scan_counts(%{total: 1_432, new: 3, relinked: 0}) ==
               "1,432 files · 3 new"
    end

    test "uses the singular for a one-file scan" do
      assert StatusHelpers.format_scan_counts(%{total: 1, new: 0, relinked: 0}) ==
               "1 file · 0 new"
    end

    test "appends relinked only when present" do
      assert StatusHelpers.format_scan_counts(%{total: 50, new: 2, relinked: 1}) ==
               "50 files · 2 new · 1 relinked"
    end
  end

  describe "metadata_kind_label/1" do
    test "maps entity kinds to friendly nouns" do
      assert StatusHelpers.metadata_kind_label(:movie) == "Movie"
      assert StatusHelpers.metadata_kind_label(:tv_series) == "Show"
      assert StatusHelpers.metadata_kind_label(:movie_series) == "Collection"
      assert StatusHelpers.metadata_kind_label(:video_object) == "Video"
    end

    test "falls back to a generic noun for an unknown kind" do
      assert StatusHelpers.metadata_kind_label(:something_else) == "Item"
    end
  end

  describe "format_enriched_title/1" do
    test "appends the year when present" do
      assert StatusHelpers.format_enriched_title(%{title: "Sample Movie", year: 2024}) ==
               "Sample Movie (2024)"
    end

    test "omits the year when missing" do
      assert StatusHelpers.format_enriched_title(%{title: "Sample Show", year: nil}) ==
               "Sample Show"
    end

    test "labels a missing title rather than rendering nil" do
      assert StatusHelpers.format_enriched_title(%{title: nil, year: 2024}) == "Untitled"
    end
  end
end
