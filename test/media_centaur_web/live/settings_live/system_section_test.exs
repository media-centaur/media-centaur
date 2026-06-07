defmodule MediaCentaurWeb.Live.SettingsLive.SystemSectionTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Live.SettingsLive.SystemSection

  describe "built_label/1" do
    test "returns a formatted UTC date for a real build" do
      info = %{
        version: "0.4.0",
        built_at: ~U[2026-04-17 12:34:56Z],
        git_sha: "abc1234"
      }

      label = SystemSection.built_label({:ok, info})
      assert label =~ "2026-04-17"
      assert label =~ "abc1234"
    end

    test "returns 'dev build' for a dev environment" do
      assert SystemSection.built_label(:dev_build) == "dev build"
    end
  end

  describe "normalize_interval_minutes/3" do
    test "parses a valid integer string" do
      assert SystemSection.normalize_interval_minutes("60", 15, 360) == 60
    end

    test "clamps below the floor up to the floor" do
      assert SystemSection.normalize_interval_minutes("5", 15, 360) == 15
    end

    test "falls back to the default on unparseable input" do
      assert SystemSection.normalize_interval_minutes("", 15, 360) == 360
      assert SystemSection.normalize_interval_minutes("abc", 15, 360) == 360
      assert SystemSection.normalize_interval_minutes(nil, 15, 360) == 360
    end

    test "ignores trailing junk after a leading integer" do
      assert SystemSection.normalize_interval_minutes("90 minutes", 15, 360) == 90
    end
  end

  describe "last_checked_label/2" do
    test "reports never when no check has run" do
      assert SystemSection.last_checked_label(:none, ~U[2026-06-07 12:00:00Z]) =~ "Never"
    end

    test "reports minutes ago" do
      at = ~U[2026-06-07 11:57:00Z]
      assert SystemSection.last_checked_label({:ok, at}, ~U[2026-06-07 12:00:00Z]) =~ "3 minutes ago"
    end

    test "reports hours ago" do
      at = ~U[2026-06-07 09:00:00Z]
      assert SystemSection.last_checked_label({:ok, at}, ~U[2026-06-07 12:00:00Z]) =~ "3 hours ago"
    end

    test "reports just now for a very recent check" do
      at = ~U[2026-06-07 11:59:30Z]
      assert SystemSection.last_checked_label({:ok, at}, ~U[2026-06-07 12:00:00Z]) =~ "just now"
    end
  end

  describe "interval_phrase/1" do
    test "renders whole hours" do
      assert SystemSection.interval_phrase(60) == "1 hour"
      assert SystemSection.interval_phrase(360) == "6 hours"
    end

    test "renders minutes when not a whole hour" do
      assert SystemSection.interval_phrase(15) == "15 minutes"
      assert SystemSection.interval_phrase(90) == "90 minutes"
    end
  end

  describe "update_schedule_label/4" do
    test "says checks are off when background checking is disabled" do
      label = SystemSection.update_schedule_label(false, 360, :none, ~U[2026-06-07 12:00:00Z])
      assert label =~ "off"
    end

    test "states the frequency and a loose next-check time" do
      last = {:ok, ~U[2026-06-07 10:00:00Z]}
      label = SystemSection.update_schedule_label(true, 360, last, ~U[2026-06-07 12:00:00Z])
      assert label =~ "every 6 hours"
      # last check 2h ago, 6h interval -> next ~4h away
      assert label =~ "about 4 hours"
    end

    test "reports any moment now when a check is overdue" do
      last = {:ok, ~U[2026-06-07 04:00:00Z]}
      label = SystemSection.update_schedule_label(true, 360, last, ~U[2026-06-07 12:00:00Z])
      assert label =~ "any moment now"
    end

    test "reports any moment now when no check has ever run" do
      label = SystemSection.update_schedule_label(true, 360, :none, ~U[2026-06-07 12:00:00Z])
      assert label =~ "any moment now"
    end

    test "uses a coarse 'less than an hour' bucket for sub-hour waits" do
      last = {:ok, ~U[2026-06-07 11:55:00Z]}
      label = SystemSection.update_schedule_label(true, 15, last, ~U[2026-06-07 12:00:00Z])
      assert label =~ "every 15 minutes"
      assert label =~ "less than an hour"
    end

    test "carries no seconds-granularity text" do
      last = {:ok, ~U[2026-06-07 11:58:30Z]}
      label = SystemSection.update_schedule_label(true, 360, last, ~U[2026-06-07 12:00:00Z])
      refute label =~ "second"
    end
  end

  describe "update_status_label/2" do
    test "idle shows a neutral prompt" do
      assert SystemSection.update_status_label(:idle, nil) =~ "Check for updates"
    end

    test "checking shows a progress message" do
      assert SystemSection.update_status_label(:checking, nil) =~ "Checking"
    end

    test "up_to_date shows an affirmative message" do
      assert SystemSection.update_status_label(:up_to_date, nil) =~ "latest"
    end

    test "update_available shows the new tag" do
      release = %{version: "0.5.0", tag: "v0.5.0", published_at: DateTime.utc_now(), html_url: "x"}
      assert SystemSection.update_status_label(:update_available, release) =~ "v0.5.0"
    end

    test "ahead_of_release acknowledges a newer local build" do
      release = %{version: "0.3.0", tag: "v0.3.0", published_at: DateTime.utc_now(), html_url: "x"}
      assert SystemSection.update_status_label(:ahead_of_release, release) =~ "ahead"
    end

    test "error produces a terse failure message" do
      assert SystemSection.update_status_label({:error, :not_found}, nil) =~ "error"
    end
  end

  describe "update_status_tone/1" do
    test "classifies statuses into tailwind tone keywords" do
      assert SystemSection.update_status_tone(:idle) == :neutral
      assert SystemSection.update_status_tone(:checking) == :neutral
      assert SystemSection.update_status_tone(:up_to_date) == :success
      assert SystemSection.update_status_tone(:update_available) == :info
      assert SystemSection.update_status_tone(:ahead_of_release) == :warning
      assert SystemSection.update_status_tone({:error, :any}) == :error
    end
  end

  describe "update_status_label/2 — rate limit" do
    test "formats a rate-limited error with the reset time" do
      reset_at = ~U[2026-04-19 15:30:00Z]
      label = SystemSection.update_status_label({:error, {:rate_limited, reset_at}}, nil)
      assert label =~ "rate limit"
      assert label =~ "15:30"
    end

    test "falls back to a generic message when reset time is unknown" do
      label = SystemSection.update_status_label({:error, {:rate_limited, nil}}, nil)
      assert label =~ "rate limit"
    end
  end

  describe "apply_visible?/1" do
    test "nil is hidden, every phase is visible" do
      refute SystemSection.apply_visible?(nil)

      for phase <- [:preparing, :downloading, :extracting, :handing_off, :done, :failed] do
        assert SystemSection.apply_visible?(phase)
      end
    end
  end

  describe "apply_phase_label/1" do
    test "returns user-readable copy per phase" do
      assert SystemSection.apply_phase_label(:preparing) =~ "Preparing"
      assert SystemSection.apply_phase_label(:downloading) =~ "Downloading"
      assert SystemSection.apply_phase_label(:extracting) =~ "Extracting"
      assert SystemSection.apply_phase_label(:handing_off) =~ "Installing"
      assert SystemSection.apply_phase_label(:done) =~ "Restarting"
      assert SystemSection.apply_phase_label(:failed) =~ "failed"
      assert SystemSection.apply_phase_label(nil) == ""
    end
  end

  describe "apply_cancelable?/1" do
    test "true before handoff, false after" do
      assert SystemSection.apply_cancelable?(:preparing)
      assert SystemSection.apply_cancelable?(:downloading)
      assert SystemSection.apply_cancelable?(:extracting)

      refute SystemSection.apply_cancelable?(:handing_off)
      refute SystemSection.apply_cancelable?(:done)
      refute SystemSection.apply_cancelable?(:failed)
      refute SystemSection.apply_cancelable?(nil)
    end
  end

  describe "apply_progress_text/1" do
    test "formats integer percents and hides unknown progress" do
      assert SystemSection.apply_progress_text(nil) == ""
      assert SystemSection.apply_progress_text(0) == "0%"
      assert SystemSection.apply_progress_text(73) == "73%"
      assert SystemSection.apply_progress_text(100) == "100%"
    end
  end

  describe "apply_error_label/1" do
    test "maps structured reasons into user-facing sentences" do
      assert SystemSection.apply_error_label({:download, :checksum_mismatch}) =~ "checksum"
      assert SystemSection.apply_error_label({:stage, :path_traversal}) =~ "rejected"
      assert SystemSection.apply_error_label({:handoff, :eaccess}) =~ "hand off"
      assert SystemSection.apply_error_label({:task_crashed, :whatever}) =~ "crashed"
    end
  end

  describe "recovery command helpers" do
    test "terminal_recovery_command/0 points at the bundled installer with --update" do
      cmd = SystemSection.terminal_recovery_command()
      assert cmd =~ "~/.local/lib/media-centaur/current/bin/media-centaur-install"
      assert cmd =~ "--update"
      refute cmd =~ "--force"
    end

    test "force_recovery_command/0 adds --force for stuck-state recovery" do
      cmd = SystemSection.force_recovery_command()
      assert cmd =~ "--update"
      assert cmd =~ "--force"
    end

    test "bootstrap_install_command/0 is a curl | sh one-liner to the public installer" do
      cmd = SystemSection.bootstrap_install_command()
      assert cmd =~ "curl"
      assert cmd =~ "| sh"
      assert cmd =~ "installer/install.sh"
    end
  end

  describe "show_release_notes?/1" do
    test "shows release notes only when an update is available" do
      assert SystemSection.show_release_notes?(:update_available)
    end

    test "hides release notes when on the latest release" do
      refute SystemSection.show_release_notes?(:up_to_date)
    end

    test "hides release notes for idle, checking, ahead, and error states" do
      refute SystemSection.show_release_notes?(:idle)
      refute SystemSection.show_release_notes?(:checking)
      refute SystemSection.show_release_notes?(:ahead_of_release)
      refute SystemSection.show_release_notes?({:error, :not_found})
    end
  end

  describe "show_terminal_recovery?/1" do
    test "shows the terminal commands only when an update is available" do
      assert SystemSection.show_terminal_recovery?(:update_available)
    end

    test "hides the terminal commands when on the latest release" do
      refute SystemSection.show_terminal_recovery?(:up_to_date)
    end

    test "hides the terminal commands for idle, checking, ahead, and error states" do
      refute SystemSection.show_terminal_recovery?(:idle)
      refute SystemSection.show_terminal_recovery?(:checking)
      refute SystemSection.show_terminal_recovery?(:ahead_of_release)
      refute SystemSection.show_terminal_recovery?({:error, :not_found})
    end
  end

  describe "tmdb_key_missing?/1" do
    test "returns true for nil, empty string, whitespace, and unrecognized shapes" do
      assert SystemSection.tmdb_key_missing?(nil)
      assert SystemSection.tmdb_key_missing?("")
      assert SystemSection.tmdb_key_missing?("   ")
      assert SystemSection.tmdb_key_missing?(%{value: ""})
      assert SystemSection.tmdb_key_missing?(%{value: nil})
      assert SystemSection.tmdb_key_missing?(:whatever)
    end

    test "returns false when a real key is present" do
      refute SystemSection.tmdb_key_missing?("abc123")
      refute SystemSection.tmdb_key_missing?(%{value: "abc123"})
    end
  end
end
