defmodule MediaCentarr.Acquisition.ViewModels.TimelineEntryTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.Pursuits.Event
  alias MediaCentarr.Acquisition.ViewModels.TimelineEntry

  defp event(attrs) do
    defaults = %{
      kind: "pursuit_started",
      occurred_at: DateTime.utc_now(:second),
      payload: %{},
      denormalized_pursuit_title: nil
    }

    struct(Event, Map.merge(defaults, Map.new(attrs)))
  end

  describe "summary line" do
    test "pursuit_started carries origin when present" do
      assert %TimelineEntry{summary: "Pursuit started (auto)"} =
               TimelineEntry.from_event(event(kind: "pursuit_started", payload: %{"origin" => "auto"}))

      assert %TimelineEntry{summary: "Pursuit started (manual)"} =
               TimelineEntry.from_event(event(kind: "pursuit_started", payload: %{"origin" => "manual"}))

      assert %TimelineEntry{summary: "Pursuit started"} =
               TimelineEntry.from_event(event(kind: "pursuit_started"))
    end

    test "release_picked appends release_title when present" do
      assert %TimelineEntry{summary: "Release picked — Sample.Show.S01E01.1080p"} =
               TimelineEntry.from_event(
                 event(
                   kind: "release_picked",
                   payload: %{"release_title" => "Sample.Show.S01E01.1080p"}
                 )
               )
    end

    test "health_changed renders both state and health transitions when both differ" do
      assert %TimelineEntry{summary: "State downloading → uploading, health healthy → frozen"} =
               TimelineEntry.from_event(
                 event(
                   kind: "health_changed",
                   payload: %{
                     "from_state" => "downloading",
                     "to_state" => "uploading",
                     "from_health" => "healthy",
                     "to_health" => "frozen"
                   }
                 )
               )
    end

    test "health_changed elides the no-change axis" do
      assert %TimelineEntry{summary: "State downloading → stalled"} =
               TimelineEntry.from_event(
                 event(
                   kind: "health_changed",
                   payload: %{
                     "from_state" => "downloading",
                     "to_state" => "stalled",
                     "from_health" => "healthy",
                     "to_health" => "healthy"
                   }
                 )
               )
    end

    test "auto_cancelled carries reason" do
      assert %TimelineEntry{summary: "Auto-cancelled (zero_seeders)"} =
               TimelineEntry.from_event(
                 event(kind: "auto_cancelled", payload: %{"reason" => "zero_seeders"})
               )
    end

    test "unknown kind falls back to the kind string" do
      assert %TimelineEntry{summary: "some_new_kind"} =
               TimelineEntry.from_event(event(kind: "some_new_kind"))
    end

    test "legacy pursuit_re_searched kind still renders" do
      assert %TimelineEntry{summary: "Re-searched Prowlarr"} =
               TimelineEntry.from_event(event(kind: "pursuit_re_searched"))
    end
  end

  describe "severity classification" do
    test "warning for stall/zero-seeders" do
      assert %TimelineEntry{severity: :warning} =
               TimelineEntry.from_event(event(kind: "stall_confirmed"))

      assert %TimelineEntry{severity: :warning} =
               TimelineEntry.from_event(event(kind: "zero_seeders_confirmed"))
    end

    test "error for identity mismatch and exhaustion" do
      assert %TimelineEntry{severity: :error} =
               TimelineEntry.from_event(event(kind: "identity_mismatch"))

      assert %TimelineEntry{severity: :error} =
               TimelineEntry.from_event(event(kind: "pursuit_exhausted"))
    end

    test "success for picked / verified / satisfied" do
      for kind <- ~w(release_picked identity_verified pursuit_satisfied) do
        assert %TimelineEntry{severity: :success} = TimelineEntry.from_event(event(kind: kind))
      end
    end

    test "info by default" do
      assert %TimelineEntry{severity: :info} =
               TimelineEntry.from_event(event(kind: "download_started"))
    end
  end

  describe "detail sub-line" do
    test "release_picked uses indexer • quality when both present" do
      assert %TimelineEntry{detail: "Indexer A • 1080p"} =
               TimelineEntry.from_event(
                 event(
                   kind: "release_picked",
                   payload: %{"indexer" => "Indexer A", "quality" => "1080p"}
                 )
               )
    end

    test "pursuit_started uses denormalized title with 'for:' prefix" do
      assert %TimelineEntry{detail: "for: Sample Show S01E03"} =
               TimelineEntry.from_event(
                 event(
                   kind: "pursuit_started",
                   denormalized_pursuit_title: "Sample Show S01E03"
                 )
               )
    end

    test "user_decision_requested uses the prompt" do
      assert %TimelineEntry{detail: "Stalled for 24+ hours — pick an alternative."} =
               TimelineEntry.from_event(
                 event(
                   kind: "user_decision_requested",
                   payload: %{"prompt" => "Stalled for 24+ hours — pick an alternative."}
                 )
               )
    end

    test "target_changed uses 'abandoned: <title>'" do
      assert %TimelineEntry{detail: "abandoned: Sample.Show.S01E01.x264"} =
               TimelineEntry.from_event(
                 event(
                   kind: "target_changed",
                   denormalized_pursuit_title: "Sample.Show.S01E01.x264"
                 )
               )
    end

    test "no detail for events without payload context" do
      assert %TimelineEntry{detail: nil} =
               TimelineEntry.from_event(event(kind: "stall_confirmed"))
    end
  end
end
