defmodule MediaCentaur.ErrorReports.ReportSubmissionTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ErrorReports
  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaur.ErrorReports.ReportPayload

  describe "ReportPayload.build/2" do
    test "renders title, full body, and labels" do
      env = %{
        app_version: "1.0.0",
        otp_release: "27",
        elixir_version: "1.18.0",
        os: "linux",
        locale: "en",
        uptime: "1h"
      }

      bucket = %Bucket{
        fingerprint: "abc123def456",
        component: :tmdb,
        normalized_message: "TMDB returned <N>: rate limited",
        display_title: "[TMDB] TMDB returned <N>: rate limited",
        severity: :error,
        count: 5,
        first_seen: ~U[2026-05-31 12:00:00Z],
        last_seen: ~U[2026-05-31 12:05:00Z],
        sample_entries: [%{timestamp: ~U[2026-05-31 12:05:00Z], message: "TMDB returned <N>"}]
      }

      payload = ReportPayload.build(bucket, env)

      assert payload.title =~ "[TMDB]"
      assert payload.body =~ "## Environment"
      assert payload.body =~ "abc123def456"
      assert payload.labels == ["incident", "auto-reported"]
    end
  end

  describe "finalize_report/1" do
    test "returns the title, body, and a prefilled public issue URL" do
      payload = %{title: "Boom", body: "the body", labels: ["incident"]}
      assert %{title: "Boom", body: "the body", issue_url: url} = ErrorReports.finalize_report(payload)
      assert url =~ "github.com/media-centaur/media-centaur/issues/new?"
      assert url =~ "title=Boom"
    end
  end

  describe "persist_user_incident/1" do
    test "persists an open :user incident" do
      snapshot = MediaCentaur.ErrorReports.ContextSnapshot.assemble(:user, %{})
      :ok = ErrorReports.persist_user_incident(%{user_description: "it broke", snapshot: snapshot})
      assert [incident | _] = ErrorReports.list_incidents()
      assert incident.origin == :user
    end

    test "never raises if the local write fails" do
      assert :ok = ErrorReports.persist_user_incident(%{user_description: "x", snapshot: %{}})
    end
  end

  describe "assemble_body/2" do
    test "prepends a narrative section when the narrative is present" do
      body = ErrorReports.assemble_body("it froze when I hit play", "## Error\nboom")
      assert body =~ "## What happened (in the user's words)"
      assert body =~ "it froze when I hit play"
      assert body =~ "## Error\nboom"
      # narrative comes before the technical body
      assert :binary.match(body, "What happened") < :binary.match(body, "## Error")
    end

    test "returns the technical body unchanged when the narrative is blank" do
      assert ErrorReports.assemble_body("", "## Error\nboom") == "## Error\nboom"
      assert ErrorReports.assemble_body("   ", "## Error\nboom") == "## Error\nboom"
    end
  end
end
