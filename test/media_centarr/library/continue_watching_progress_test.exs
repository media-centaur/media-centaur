defmodule MediaCentarr.Library.ContinueWatchingProgressTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Library.ContinueWatchingProgress

  describe "compute_pct/1" do
    # The Continue Watching bar's contract is small but counter-intuitive:
    # it blends episode-completion count with current-episode position.
    # Each test below is one row of the truth table — the file reads as a
    # spec for "what does N % mean in this UI?".

    test "nil summary → 0" do
      # No progress at all (entity in Continue Watching but summary still
      # being computed) → empty bar, never crash.
      assert ContinueWatchingProgress.compute_pct(nil) == 0
    end

    test "zero episodes → 0 (defends against division by zero)" do
      summary = %{episodes_total: 0, episodes_completed: 0}
      assert ContinueWatchingProgress.compute_pct(summary) == 0
    end

    test "movie at 50 % position → 50" do
      # The headline regression: previously 0 % until the movie finished.
      summary = %{
        episodes_total: 1,
        episodes_completed: 0,
        episode_position_seconds: 50.0,
        episode_duration_seconds: 100.0
      }

      assert ContinueWatchingProgress.compute_pct(summary) == 50
    end

    test "movie just started (1 second of 100) → 1" do
      # A user opening a movie should see the bar move off zero — proves
      # we don't accidentally floor to zero for tiny fractions.
      summary = %{
        episodes_total: 1,
        episodes_completed: 0,
        episode_position_seconds: 1.0,
        episode_duration_seconds: 100.0
      }

      assert ContinueWatchingProgress.compute_pct(summary) == 1
    end

    test "TV series 5/10 done plus halfway through #6 → 55" do
      # Counter-intuitive at first read: "5 of 10" plus mid-episode reads
      # as 55 %, not 50 % (which would ignore #6) and not 60 % (which
      # would over-credit #6).
      summary = %{
        episodes_total: 10,
        episodes_completed: 5,
        episode_position_seconds: 500.0,
        episode_duration_seconds: 1000.0
      }

      assert ContinueWatchingProgress.compute_pct(summary) == 55
    end

    test "TV series 5/10 done with no current-episode position → 50" do
      # Completed only — the user has not started the next episode yet.
      summary = %{
        episodes_total: 10,
        episodes_completed: 5,
        episode_position_seconds: 0.0,
        episode_duration_seconds: 0.0
      }

      assert ContinueWatchingProgress.compute_pct(summary) == 50
    end

    test "missing position/duration keys default to 0 / 0 (no current-fraction credit)" do
      # Tolerates the legacy summary shape that fetch_in_progress_*
      # functions used to produce. Without this, the bar would crash on
      # any pre-migration cached data.
      summary = %{episodes_total: 4, episodes_completed: 1}
      assert ContinueWatchingProgress.compute_pct(summary) == 25
    end

    test "duration zero → no current-fraction credit" do
      # A WatchProgress row created the moment playback started may have
      # `duration_seconds: 0` until mpv sends the first metadata update.
      # Don't divide by zero, don't credit.
      summary = %{
        episodes_total: 1,
        episodes_completed: 0,
        episode_position_seconds: 30.0,
        episode_duration_seconds: 0.0
      }

      assert ContinueWatchingProgress.compute_pct(summary) == 0
    end

    test "position exceeds duration → caps at 1.0 (defends against revised durations)" do
      # If a duration is revised down (e.g. mpv corrected itself after
      # parsing the file's actual length), position can briefly exceed
      # duration. Bar must not exceed 100 %.
      summary = %{
        episodes_total: 1,
        episodes_completed: 0,
        episode_position_seconds: 200.0,
        episode_duration_seconds: 100.0
      }

      assert ContinueWatchingProgress.compute_pct(summary) == 100
    end

    test "movie marked completed → 100" do
      # Defensive: completed movies are filtered out of `list_in_progress`
      # before this function runs, but if one slips through (e.g. via
      # cached state) the bar should read full, not empty. Also pins the
      # short-circuit clause that prevents `(1 + 1.0) / 1 * 100 = 200`.
      summary = %{
        episodes_total: 1,
        episodes_completed: 1,
        episode_position_seconds: 100.0,
        episode_duration_seconds: 100.0
      }

      assert ContinueWatchingProgress.compute_pct(summary) == 100
    end

    test "TV series with all episodes completed → 100" do
      # Same short-circuit for series: 24/24 done with stale position
      # info on the last episode must read 100, not 124.
      summary = %{
        episodes_total: 24,
        episodes_completed: 24,
        episode_position_seconds: 1000.0,
        episode_duration_seconds: 1000.0
      }

      assert ContinueWatchingProgress.compute_pct(summary) == 100
    end

    test "episodes_completed exceeds episodes_total → 100 (defensive cap)" do
      # Pathological state — should never happen but the clause is
      # `>=`, not `==`, so any "more completed than exist" snapshot
      # caps at 100 instead of returning a value above 100.
      summary = %{episodes_total: 5, episodes_completed: 7}
      assert ContinueWatchingProgress.compute_pct(summary) == 100
    end

    test "result is always an integer (the bar template interpolates without rounding)" do
      summary = %{
        episodes_total: 3,
        episodes_completed: 1,
        episode_position_seconds: 333.0,
        episode_duration_seconds: 1000.0
      }

      result = ContinueWatchingProgress.compute_pct(summary)
      assert is_integer(result)
      # (1 + 0.333) / 3 * 100 = 44.43 → trunc = 44
      assert result == 44
    end
  end

  describe "current_position_summary/1" do
    # The bar wants the position of the episode the user is mid-way
    # through — not the most-recently-watched-overall record (which
    # might be a completed episode the user finished and then stopped).

    test "empty list → zeros" do
      assert ContinueWatchingProgress.current_position_summary([]) == %{
               episode_position_seconds: 0.0,
               episode_duration_seconds: 0.0
             }
    end

    test "single in-progress record → its position and duration" do
      record = %{
        completed: false,
        position_seconds: 250.0,
        duration_seconds: 1000.0,
        last_watched_at: ~U[2026-05-01 12:00:00Z]
      }

      assert ContinueWatchingProgress.current_position_summary([record]) == %{
               episode_position_seconds: 250.0,
               episode_duration_seconds: 1000.0
             }
    end

    test "all records completed → zeros (no current item)" do
      # Series fully watched but a stale row in cache still has these
      # records. Continue Watching shouldn't credit the LAST completed
      # episode's runtime as the current position.
      records = [
        %{
          completed: true,
          position_seconds: 1000.0,
          duration_seconds: 1000.0,
          last_watched_at: ~U[2026-05-01 12:00:00Z]
        }
      ]

      assert ContinueWatchingProgress.current_position_summary(records) == %{
               episode_position_seconds: 0.0,
               episode_duration_seconds: 0.0
             }
    end

    test "completed records are skipped in favor of in-progress ones" do
      # The "most recent completed" episode shouldn't be picked over an
      # earlier-watched-but-still-in-progress one. Resume semantics: the
      # user wants to finish what they started, not re-start what they
      # finished.
      old_in_progress = %{
        completed: false,
        position_seconds: 100.0,
        duration_seconds: 1000.0,
        last_watched_at: ~U[2026-05-01 09:00:00Z]
      }

      newer_completed = %{
        completed: true,
        position_seconds: 1000.0,
        duration_seconds: 1000.0,
        last_watched_at: ~U[2026-05-01 12:00:00Z]
      }

      assert ContinueWatchingProgress.current_position_summary([
               newer_completed,
               old_in_progress
             ]) == %{
               episode_position_seconds: 100.0,
               episode_duration_seconds: 1000.0
             }
    end

    test "multiple in-progress records → most recent by last_watched_at wins" do
      # User starts ep 5, then jumps to ep 7. Bar should reflect ep 7,
      # not ep 5.
      ep_5 = %{
        completed: false,
        position_seconds: 100.0,
        duration_seconds: 1000.0,
        last_watched_at: ~U[2026-05-01 09:00:00Z]
      }

      ep_7 = %{
        completed: false,
        position_seconds: 700.0,
        duration_seconds: 1000.0,
        last_watched_at: ~U[2026-05-01 12:00:00Z]
      }

      assert ContinueWatchingProgress.current_position_summary([ep_5, ep_7]) == %{
               episode_position_seconds: 700.0,
               episode_duration_seconds: 1000.0
             }
    end

    test "nil position/duration on the picked record → 0.0 fallbacks" do
      # WatchProgress rows can have nil position when freshly created
      # before mpv reports anything. Don't propagate nil into the bar.
      record = %{
        completed: false,
        position_seconds: nil,
        duration_seconds: nil,
        last_watched_at: ~U[2026-05-01 12:00:00Z]
      }

      assert ContinueWatchingProgress.current_position_summary([record]) == %{
               episode_position_seconds: 0.0,
               episode_duration_seconds: 0.0
             }
    end
  end
end
