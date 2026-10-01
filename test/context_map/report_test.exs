defmodule MediaCentaur.ContextMap.ReportTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Report

  @finding %Finding{
    rule: "R3",
    owner: MediaCentaur.Discovery,
    schema: MediaCentaur.Discovery.TitleIntent,
    field: :rung,
    value: :ignored,
    consumer: MediaCentaurWeb.Components.Title.Logic,
    consumer_context: :web,
    surfaces: [MediaCentaurWeb.IncomingLive],
    anchored?: true,
    file: "lib/media_centaur_web/components/title/logic.ex",
    line: 189,
    detail: nil
  }

  test "a finding serialises with its key, module names as strings, and verdict fields" do
    [encoded] =
      Report.encode_findings([@finding], %{
        Finding.key(@finding) => %{"verdict" => "leak", "reason" => "search marker"}
      })

    assert encoded == %{
             key:
               "R3|MediaCentaur.Discovery.TitleIntent|rung|ignored|MediaCentaurWeb.Components.Title.Logic",
             rule: "R3",
             owner: "MediaCentaur.Discovery",
             schema: "MediaCentaur.Discovery.TitleIntent",
             field: "rung",
             value: "ignored",
             consumer: "MediaCentaurWeb.Components.Title.Logic",
             consumer_context: "web",
             surfaces: ["MediaCentaurWeb.IncomingLive"],
             anchored: true,
             file: "lib/media_centaur_web/components/title/logic.ex",
             line: 189,
             detail: nil,
             verdict: "leak",
             reason: "search marker"
           }
  end

  test "check reports unverdicted findings and stale verdicts" do
    assert {:error,
            %{
              unverdicted: [
                "R3|MediaCentaur.Discovery.TitleIntent|rung|ignored|MediaCentaurWeb.Components.Title.Logic"
              ],
              stale: ["R9|gone"]
            }} = Report.check([@finding], %{"R9|gone" => %{"verdict" => "allowed", "reason" => "x"}})

    assert :ok =
             Report.check([@finding], %{Finding.key(@finding) => %{"verdict" => "leak", "reason" => "y"}})
  end

  test "verdicts file parses into a map by key and rejects an unknown verdict" do
    assert %{"R3|a" => %{"verdict" => "leak", "reason" => "r"}} =
             Report.parse_verdicts(~s([{"key": "R3|a", "verdict": "leak", "reason": "r"}]))

    assert_raise ArgumentError, ~r/rule wrong/, fn ->
      Report.parse_verdicts(~s([{"key": "R3|a", "verdict": "rule wrong", "reason": "r"}]))
    end
  end

  test "the full document is deterministic" do
    assert MediaCentaur.ContextMap.build(%{}) == MediaCentaur.ContextMap.build(%{})
  end
end
