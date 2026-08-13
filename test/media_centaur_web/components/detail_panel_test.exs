defmodule MediaCentaurWeb.Components.DetailPanelTest do
  use ExUnit.Case, async: true

  import MediaCentaur.TestFactory

  alias MediaCentaurWeb.Components.Detail.Logic
  alias MediaCentaurWeb.Components.Detail.PlayableRow
  alias MediaCentaurWeb.Components.DetailPanel

  describe "scrollable_content?/2" do
    # Entities arrive as the loose modal-entry map shape (`entity: :map`
    # on the component) — minimal maps mirror that contract.

    test "true for TV series regardless of view" do
      assert DetailPanel.scrollable_content?(%{type: :tv_series}, :main)
    end

    test "false for a movie series without extras on the main view — the rail lives in the pinned block (UIDR-023)" do
      refute DetailPanel.scrollable_content?(%{type: :movie_series, extras: []}, :main)
    end

    test "true for a movie series carrying entity-level extras" do
      extra = build_extra(%{owner_type: :movie_series})
      assert DetailPanel.scrollable_content?(%{type: :movie_series, extras: [extra]}, :main)
    end

    test "false for a bare movie on the main view" do
      refute DetailPanel.scrollable_content?(%{type: :movie, extras: []}, :main)
    end

    test "true for any entity on the Manage or Cast sub-views" do
      assert DetailPanel.scrollable_content?(%{type: :movie, extras: []}, :info)
      assert DetailPanel.scrollable_content?(%{type: :movie, extras: []}, :cast)
    end

    test "true for a movie carrying entity-level extras" do
      extra = build_extra(%{owner_type: :movie})

      assert DetailPanel.scrollable_content?(%{type: :movie, extras: [extra]}, :main)
    end

    test "season-owned extras alone do not make a movie scrollable" do
      extra = build_extra(%{owner_type: :season})

      refute DetailPanel.scrollable_content?(%{type: :movie, extras: [extra]}, :main)
    end
  end

  describe "blur_spoilers?/2" do
    test "blurs a fully-unwatched episode in spoiler-free mode" do
      assert PlayableRow.blur_spoilers?(true, :unwatched)
    end

    test "never blurs a watched or in-progress episode, even in spoiler-free mode" do
      refute PlayableRow.blur_spoilers?(true, :watched)
      refute PlayableRow.blur_spoilers?(true, :current)
    end

    test "never blurs when spoiler-free mode is off" do
      refute PlayableRow.blur_spoilers?(false, :unwatched)
    end
  end

  # `delete_gesture_state/3` and `delete_in_flight?/1` moved to
  # `MediaCentaurWeb.LiveHelpers` (see live_helpers_test.exs) — shared with
  # Review's delete gesture, no longer DetailPanel-specific.

  # `auto_expand_season/2` was removed by the 2026-08-04 orientation
  # design — seasons always open collapsed; the hero orientation block
  # answers "where am I".

  # --- overall_progress_percent/2 ---
  #
  # Leaf-only: containers (tv_series / movie_series) carry their
  # progress in the hero orientation hairline, so the card-row percent
  # and remaining copy are never computed for them (Stage 2 of the
  # collection-detail-coherence campaign).

  describe "overall_progress_percent/2" do
    test "returns 0 for nil progress" do
      assert DetailPanel.overall_progress_percent(nil, build_entity()) == 0
    end

    test "computes position-based percentage for standalone movie" do
      progress = %{
        episode_position_seconds: 1800.0,
        episode_duration_seconds: 3600.0,
        episodes_completed: 0
      }

      entity = build_entity(%{type: :movie})

      assert DetailPanel.overall_progress_percent(progress, entity) == 50
    end

    test "returns 100 when completed but no duration for movie" do
      progress = %{
        episode_position_seconds: 0.0,
        episode_duration_seconds: 0.0,
        episodes_completed: 1
      }

      entity = build_entity(%{type: :movie})

      assert DetailPanel.overall_progress_percent(progress, entity) == 100
    end

    test "caps at 100" do
      progress = %{
        episode_position_seconds: 4000.0,
        episode_duration_seconds: 3600.0,
        episodes_completed: 0
      }

      entity = build_entity(%{type: :movie})

      assert DetailPanel.overall_progress_percent(progress, entity) == 100
    end
  end

  # --- progress_remaining_text/2 ---
  #
  # UIDR-024: the remaining figure is a metadata-line item ("1h left"),
  # not card-row copy. A completed title yields nil — the full hairline
  # and the watched toggle carry that state; the metadata line goes back
  # to showing the status.

  describe "progress_remaining_text/2" do
    test "returns nil for nil progress" do
      assert DetailPanel.progress_remaining_text(nil, build_entity()) == nil
    end

    # No container cases: TV and collection remaining-text moved to the
    # hero orientation hairline (`MediaCentaurWeb.ViewModel.Orientation`);
    # the remaining metadata item exists only for leaves.

    test "returns nil for completed standalone movie" do
      progress = %{
        episodes_completed: 1,
        episode_duration_seconds: 0.0,
        episode_position_seconds: 0.0
      }

      entity = build_entity(%{type: :movie})

      assert DetailPanel.progress_remaining_text(progress, entity) == nil
    end

    test "returns time left for in-progress standalone movie" do
      progress = %{
        episodes_completed: 0,
        episode_duration_seconds: 7200.0,
        episode_position_seconds: 3600.0
      }

      entity = build_entity(%{type: :movie})

      assert DetailPanel.progress_remaining_text(progress, entity) == "1h left"
    end
  end

  # --- episode_state/1 ---

  describe "state_from_progress/1" do
    test "returns :unwatched for nil" do
      assert PlayableRow.state_from_progress(nil) == :unwatched
    end

    test "returns :watched when completed" do
      progress = %{completed: true, position_seconds: 2700.0}
      assert PlayableRow.state_from_progress(progress) == :watched
    end

    test "returns :current when has position" do
      progress = %{completed: false, position_seconds: 100.0}
      assert PlayableRow.state_from_progress(progress) == :current
    end

    test "returns :unwatched when no position and not completed" do
      progress = %{completed: false, position_seconds: 0.0}
      assert PlayableRow.state_from_progress(progress) == :unwatched
    end
  end

  # --- episode_row_class/2 ---

  describe "row_class/2" do
    test "returns primary highlight when resume target" do
      assert PlayableRow.row_class(:watched, true) == "bg-primary/10"
    end

    test "returns opacity for watched" do
      assert PlayableRow.row_class(:watched, false) == "opacity-60"
    end

    test "returns info bg for current" do
      assert PlayableRow.row_class(:current, false) == "bg-info/5"
    end

    test "returns empty for unwatched" do
      assert PlayableRow.row_class(:unwatched, false) == ""
    end
  end

  # --- progress_percent/1 ---

  describe "progress_percent/1" do
    test "computes percentage from position and duration" do
      assert PlayableRow.progress_percent(%{position_seconds: 900, duration_seconds: 3600}) == 25
    end

    test "caps at 100" do
      assert PlayableRow.progress_percent(%{position_seconds: 4000, duration_seconds: 3600}) ==
               100
    end

    test "returns 0 for nil" do
      assert PlayableRow.progress_percent(nil) == 0
    end

    test "returns 0 when duration is 0" do
      assert PlayableRow.progress_percent(%{position_seconds: 100, duration_seconds: 0}) == 0
    end
  end

  # Manage-sheet helpers (file_tech_line, format_file_size, file_summary,
  # build_file_groups, build_delete_all_payload) moved to
  # `Detail.ManagePanelTest` with the 2026-08-08 Manage extraction.
  # `build_episode_list/2` and `count_watched_episodes/2` were
  # extracted into `MediaCentaurWeb.ViewModel.SeriesDetail` (see
  # `test/media_centaur_web/view_model/series_detail_test.exs`) when
  # the TV-series path migrated to typed view-models. Behavioural
  # coverage lives there now: gap-filling, watched_count, total_count.

  describe "upcoming_pill_copy/2" do
    test "future date within 14 days reads 'in Xd'" do
      today = ~D[2026-05-08]
      assert Logic.upcoming_pill_copy(%{air_date: ~D[2026-05-15]}, today) == "in 7d"
      assert Logic.upcoming_pill_copy(%{air_date: ~D[2026-05-09]}, today) == "in 1d"
    end

    test "today reads 'today'" do
      today = ~D[2026-05-08]
      assert Logic.upcoming_pill_copy(%{air_date: ~D[2026-05-08]}, today) == "today"
    end

    test "past date within 14 days reads 'aired Xd ago'" do
      today = ~D[2026-05-08]
      assert Logic.upcoming_pill_copy(%{air_date: ~D[2026-05-05]}, today) == "aired 3d ago"
      assert Logic.upcoming_pill_copy(%{air_date: ~D[2026-05-07]}, today) == "aired 1d ago"
    end

    test "further-out future date renders the formatted month/day" do
      today = ~D[2026-05-08]
      assert Logic.upcoming_pill_copy(%{air_date: ~D[2026-08-15]}, today) == "Aug 15"
    end

    test "further-out past date renders the formatted month/day" do
      today = ~D[2026-05-08]
      assert Logic.upcoming_pill_copy(%{air_date: ~D[2026-01-04]}, today) == "Jan 4"
    end

    test "nil air_date renders 'TBA'" do
      assert Logic.upcoming_pill_copy(%{air_date: nil}, ~D[2026-05-08]) == "TBA"
    end
  end
end
