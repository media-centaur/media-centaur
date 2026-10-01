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

  test "a verdict entry missing key, verdict or reason raises naming the entry" do
    assert_raise ArgumentError, ~r/"verdict" => "leak"/, fn ->
      Report.parse_verdicts(~s([{"verdict": "leak", "reason": "r"}]))
    end

    assert_raise ArgumentError, ~r/R3\|a/, fn ->
      Report.parse_verdicts(~s([{"key": "R3|a", "verdict": "leak"}]))
    end
  end

  @tag :tmp_dir
  test "a missing verdicts file is no verdicts; any other read error raises", %{tmp_dir: tmp_dir} do
    assert Report.read_verdicts(Path.join(tmp_dir, "absent.json")) == %{}
    assert_raise File.Error, fn -> Report.read_verdicts(tmp_dir) end
  end

  test "the analysis and the full document are deterministic" do
    analysis = MediaCentaur.ContextMap.analyse()
    assert analysis == MediaCentaur.ContextMap.analyse()

    assert MediaCentaur.ContextMap.document(analysis, %{}) ==
             MediaCentaur.ContextMap.document(analysis, %{})
  end

  test "the analysis findings carry their surfaces and are sorted by key then line" do
    %{findings: findings} = MediaCentaur.ContextMap.analyse()
    assert findings == Enum.sort_by(findings, &{Finding.key(&1), &1.line})
    assert Enum.any?(findings, &(&1.surfaces != []))
  end
end
