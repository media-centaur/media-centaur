defmodule MediaCentaur.ErrorReports.ReportPayloadTest do
  use ExUnit.Case, async: true
  alias MediaCentaur.ErrorReports.ReportPayload

  test "build_generic/2 renders a title + body from a snapshot and env" do
    snapshot = %{
      "lead_up" => [
        %{
          "ts" => "2026-06-01T00:00:00Z",
          "level" => "error",
          "component" => "tmdb",
          "message" => "boom",
          "correlated" => false
        }
      ],
      "vitals" => %{"tmdb" => %{"ok" => true}},
      "contributor" => %{},
      "triggering_ids" => %{},
      "crash_reason" => nil
    }

    env = %{
      app_version: "1.2.3",
      otp_release: "27",
      elixir_version: "1.19",
      os: "linux",
      locale: "en",
      uptime: "1h"
    }

    %{title: title, body: body, labels: labels} = ReportPayload.build_generic(snapshot, env)

    assert title =~ "report"
    assert body =~ "Environment"
    assert body =~ "boom"
    assert "incident" in labels
  end
end
