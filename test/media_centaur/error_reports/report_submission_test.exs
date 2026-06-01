defmodule MediaCentaur.ErrorReports.ReportSubmissionTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.ErrorReports
  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaur.ErrorReports.ReportPayload

  defmodule OkTransport do
    @behaviour MediaCentaur.ErrorReports.ReportTransport
    @impl true
    def submit(_payload, _opts), do: {:ok, "https://github.com/owner/reports/issues/42"}
  end

  defmodule FailTransport do
    @behaviour MediaCentaur.ErrorReports.ReportTransport
    @impl true
    def submit(_payload, _opts), do: {:error, :no_token}
  end

  defp bucket do
    %Bucket{
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
  end

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

      payload = ReportPayload.build(bucket(), env)

      assert payload.title =~ "[TMDB]"
      assert payload.body =~ "## Environment"
      assert payload.body =~ "abc123def456"
      assert payload.labels == ["incident", "auto-reported"]
    end
  end

  describe "submit_report/2" do
    test "returns {:ok, url} when the transport succeeds" do
      assert {:ok, "https://github.com/owner/reports/issues/42"} =
               ErrorReports.submit_report(bucket(), transport: OkTransport)
    end

    test "falls back to a copyable bundle when the transport fails" do
      assert {:fallback, bundle} = ErrorReports.submit_report(bucket(), transport: FailTransport)

      assert bundle =~ "[TMDB]"
      assert bundle =~ "## Environment"
    end
  end

  describe "submit_payload/2" do
    test "submits an already-built payload as-is" do
      payload = %{title: "T", body: "edited body", labels: ["incident"]}
      assert {:ok, "https://github.com/owner/reports/issues/42"} =
               ErrorReports.submit_payload(payload, transport: OkTransport)
    end

    test "falls back to the payload's own text on transport failure" do
      payload = %{title: "T", body: "edited body", labels: ["incident"]}
      assert {:fallback, bundle} = ErrorReports.submit_payload(payload, transport: FailTransport)
      assert bundle =~ "T"
      assert bundle =~ "edited body"
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
