defmodule MediaCentaur.ContextMap.FindingTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Finding

  test "key is rule, schema, field, value, consumer — stable across runs and lines" do
    finding = %Finding{
      rule: "R3",
      owner: MediaCentaur.Discovery,
      schema: MediaCentaur.Discovery.TitleIntent,
      field: :rung,
      value: :ignored,
      consumer: MediaCentaurWeb.Components.Title.Logic,
      consumer_context: :web,
      surfaces: [],
      anchored?: true,
      file: "lib/media_centaur_web/components/title/logic.ex",
      line: 189,
      detail: nil
    }

    assert Finding.key(finding) ==
             "R3|MediaCentaur.Discovery.TitleIntent|rung|ignored|MediaCentaurWeb.Components.Title.Logic"

    assert Finding.key(%{finding | line: 500}) == Finding.key(finding)
  end
end
