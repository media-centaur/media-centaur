defmodule MediaCentaur.ContextMap.HtmlTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Html

  @document %{
    contexts: [
      %{
        name: "MediaCentaur.Discovery",
        kernel: false,
        deps: ["MediaCentaur.Library"],
        exports: ["MediaCentaur.Discovery.TitleIntent"],
        schemas: [
          %{
            module: "MediaCentaur.Discovery.TitleIntent",
            table: "title_intents",
            fields: [
              %{
                name: "rung",
                type: "Ecto.Enum",
                values: ["ignored", "list"],
                reads: %{"MediaCentaur.Discovery" => 2, "web" => 3},
                writes: %{"MediaCentaur.Discovery" => 1}
              }
            ],
            associations: [
              %{
                name: "sample_parent",
                kind: "belongs_to",
                target: "MediaCentaur.Discovery.SampleParent",
                foreign_key: "sample_parent_id"
              }
            ]
          }
        ]
      },
      %{name: "MediaCentaur.Library", kernel: true, deps: [], exports: [], schemas: []}
    ],
    kernel_reads: [
      %{
        owner: "MediaCentaur.Discovery",
        schema: "MediaCentaur.Discovery.TitleIntent",
        field: "tmdb_id",
        target: "external"
      }
    ],
    findings: [
      %{
        key: "R3|MediaCentaur.Discovery.TitleIntent|rung|ignored|MediaCentaurWeb.Components.Title.Logic",
        rule: "R3",
        owner: "MediaCentaur.Discovery",
        schema: "MediaCentaur.Discovery.TitleIntent",
        field: "rung",
        value: "ignored",
        consumer: "MediaCentaurWeb.Components.Title.Logic",
        consumer_context: "web",
        surfaces: ["MediaCentaurWeb.IncomingLive"],
        anchored: true,
        file: "lib/x.ex",
        line: 189,
        detail: nil,
        verdict: nil,
        reason: nil
      }
    ]
  }

  test "renders matrix, panels and findings with the finding key, and escapes" do
    html = Html.render(@document)

    assert html =~ "<title>Context map</title>"

    assert html =~
             "R3|MediaCentaur.Discovery.TitleIntent|rung|ignored|MediaCentaurWeb.Components.Title.Logic"

    assert html =~ "title_intents"
    assert html =~ "MediaCentaurWeb.IncomingLive"

    assert html
           |> LazyHTML.from_document()
           |> LazyHTML.query(~s([data-cell="MediaCentaur.Discovery→web"]))
           |> Enum.count() == 1

    refute html =~ "<script src="
  end

  test "an association row shows its name, kind, target and foreign key" do
    html = Html.render(@document)

    for text <- [
          "sample_parent",
          "belongs_to",
          "MediaCentaur.Discovery.SampleParent",
          "sample_parent_id"
        ] do
      assert html =~ text
    end
  end

  test "escapes reasons" do
    finding = Map.merge(hd(@document.findings), %{verdict: "leak", reason: "<b>x</b>"})
    html = Html.render(%{@document | findings: [finding]})
    assert html =~ "&lt;b&gt;x&lt;/b&gt;"
    refute html =~ "<b>x</b>"
  end
end
