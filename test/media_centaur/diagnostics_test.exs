defmodule MediaCentaur.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Diagnostics
  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaur.ErrorReports.Incident

  defp bucket(overrides \\ []) do
    now = ~U[2026-06-08 10:42:00.000000Z]

    struct!(
      %Bucket{
        fingerprint: "fp_watcher_mount",
        component: :watcher,
        normalized_message: "watch path not accessible — <path> (waiting for mount)",
        display_title: "[Watcher] watch path not accessible",
        severity: :warning,
        count: 3,
        first_seen: DateTime.add(now, -600, :second),
        last_seen: now,
        sample_entries: [],
        headline: "watch path not accessible — <path> (waiting for mount)"
      },
      overrides
    )
  end

  defp incident(overrides \\ []) do
    now = ~U[2026-06-08 10:42:00.000000Z]

    struct!(
      %Incident{
        id: "95e0a7c8-c7df-4b30-b1ce-16a263c76b52",
        origin: :log,
        component: "pipeline",
        kind: nil,
        message: "[Pipeline] sample failure",
        display_title: "Sample failure",
        fingerprint: "fp_sample",
        severity: :error,
        status: :open,
        count: 4,
        first_seen: DateTime.add(now, -600, :second),
        last_seen: now,
        app_version_at_first: "0.82.4"
      },
      overrides
    )
  end

  defp frozen_context do
    %{
      "lead_up" => [
        %{
          "ts" => "2026-06-08T10:41:50.000000Z",
          "level" => "info",
          "component" => "watcher",
          "message" => "scanned dir",
          "correlated" => false
        },
        %{
          "ts" => "2026-06-08T10:41:55.000000Z",
          "level" => "error",
          "component" => "pipeline",
          "message" => "boom near sample-123",
          "correlated" => true
        }
      ],
      "vitals" => %{"tmdb" => %{"ok" => true}, "watcher" => %{"queue" => 3}},
      "contributor" => %{"detail" => "stage import failed"},
      "triggering_ids" => %{"sample_id" => "sample-123"},
      "crash_reason" => nil
    }
  end

  describe "format_issues/1" do
    test "reports an empty state when the board is clean" do
      assert Diagnostics.format_issues([]) =~ "No issues"
    end

    test "shows fingerprint, severity, count, and headline per issue" do
      output = Diagnostics.format_issues([bucket()])

      assert output =~ "fp_watcher_mount"
      assert output =~ "warning"
      assert output =~ "3"
      assert output =~ "watch path not accessible"
    end

    test "groups issues by subsystem" do
      output =
        Diagnostics.format_issues([
          bucket(),
          bucket(fingerprint: "fp_prowlarr", component: :acquisition, severity: :error)
        ])

      assert output =~ "watcher"
      assert output =~ "acquisition"
      assert output =~ "fp_prowlarr"
    end
  end

  describe "format_incident_list/1" do
    test "reports an empty state when there are no incidents" do
      output = Diagnostics.format_incident_list([])
      assert output =~ "No incidents"
    end

    test "shows a short id, severity, status, and title per incident" do
      output = Diagnostics.format_incident_list([incident()])

      assert output =~ "95e0a7c8"
      assert output =~ "error"
      assert output =~ "open"
      assert output =~ "Sample failure"
    end
  end

  describe "format_incident/1" do
    test "renders header fields for the incident" do
      output = Diagnostics.format_incident(incident())

      assert output =~ "95e0a7c8"
      assert output =~ "Sample failure"
      assert output =~ "[Pipeline] sample failure"
      assert output =~ "pipeline"
      assert output =~ "fp_sample"
      assert output =~ "0.82.4"
      assert output =~ "4"
    end

    test "renders the frozen context: vitals, contributor, triggering ids, and lead-up" do
      output = Diagnostics.format_incident(incident(latest_context: frozen_context()))

      assert output =~ "tmdb"
      assert output =~ "stage import failed"
      assert output =~ "sample-123"
      assert output =~ "scanned dir"
      assert output =~ "boom near sample-123"
    end

    test "flags lead-up lines that share a triggering id as correlated" do
      output = Diagnostics.format_incident(incident(latest_context: frozen_context()))

      correlated_line =
        output
        |> String.split("\n")
        |> Enum.find(&(&1 =~ "boom near sample-123"))

      assert correlated_line =~ "correlated"
    end

    test "falls back to first_context when latest_context is absent" do
      output =
        Diagnostics.format_incident(incident(first_context: frozen_context(), latest_context: nil))

      assert output =~ "stage import failed"
    end

    test "notes the absence of a frozen context" do
      output = Diagnostics.format_incident(incident(first_context: nil, latest_context: nil))

      assert output =~ "No frozen context"
    end

    test "surfaces the user's narrative for a :user incident" do
      output =
        Diagnostics.format_incident(
          incident(
            origin: :user,
            component: "user",
            display_title: "User report",
            user_description: "The home page looked wrong"
          )
        )

      assert output =~ "The home page looked wrong"
    end
  end
end
