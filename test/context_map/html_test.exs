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
      %{
        name: "MediaCentaur.Library",
        kernel: true,
        deps: [],
        exports: [],
        schemas: [
          %{
            module: "MediaCentaur.Library.Movie",
            table: "library_movies",
            fields: [],
            associations: []
          }
        ]
      },
      %{name: "MediaCentaur.Quiet", kernel: false, deps: [], exports: [], schemas: []}
    ],
    kernel_reads: [
      %{
        owner: "MediaCentaur.Discovery",
        schema: "MediaCentaur.Discovery.TitleIntent",
        field: "tmdb_id",
        target: "external"
      },
      %{
        owner: "MediaCentaur.Discovery",
        schema: "MediaCentaur.Discovery.TitleIntent",
        field: "movie_id",
        target: "MediaCentaur.Library.Movie"
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
        excerpt: ~s|defp rung_marker(:ignored), do: "Ignored"|,
        concept_key: "R3|MediaCentaur.Discovery.TitleIntent|rung|ignored|*",
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

    assert html |> query(~s(.panel[data-context="MediaCentaur.Discovery"])) |> LazyHTML.text() =~
             "title_intents"

    assert html |> query(".consumer") |> LazyHTML.text() =~ "MediaCentaurWeb.IncomingLive"

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

  defp query(html, selector), do: html |> LazyHTML.from_document() |> LazyHTML.query(selector)

  test "a kernel read shades its owner→target-context cell with its count" do
    [cell] =
      @document
      |> Html.render()
      |> query(~s([data-cell="MediaCentaur.Discovery→MediaCentaur.Library"]))
      |> Enum.to_list()

    assert LazyHTML.attribute(cell, "class") == ["kernel"]
    assert LazyHTML.attribute(cell, "title") == ["1 shared-kernel reads"]
    assert LazyHTML.text(cell) =~ "1"
  end

  test "a context without schemas or findings is listed under the matrix, not given a row, column or panel" do
    html = Html.render(@document)

    assert html |> query(~s(.matrix [title="MediaCentaur.Quiet"])) |> Enum.empty?()
    assert html |> query(~s([data-cell^="MediaCentaur.Quiet"])) |> Enum.empty?()
    assert html |> query(~s(.panel[data-context="MediaCentaur.Quiet"])) |> Enum.empty?()
    assert html |> query(".empty-contexts") |> LazyHTML.text() =~ "Quiet"
  end

  test "findings carry their owner and consumer, cells carry their pair, and both filters list them" do
    html = Html.render(@document)

    assert html
           |> query(~s(.finding[data-owner="MediaCentaur.Discovery"][data-consumer="web"]))
           |> Enum.count() == 1

    assert html
           |> query(~s(td[data-owner="MediaCentaur.Discovery"][data-consumer="web"]))
           |> Enum.count() == 1

    assert html
           |> query(~s(select[data-filter="owner"] option[value="MediaCentaur.Discovery"]))
           |> Enum.count() == 1

    assert html |> query(~s(select[data-filter="consumer"] option[value="web"])) |> Enum.count() == 1
  end

  test "an exported schema carries the exported chip" do
    assert @document |> Html.render() |> query(".chip.exported") |> LazyHTML.text() == "exported"
  end

  test "findings sharing rule, schema, field and value render in one concept block, each consumer with its sites" do
    first = hd(@document.findings)

    second =
      Map.merge(first, %{
        key: "R3|MediaCentaur.Discovery.TitleIntent|rung|ignored|MediaCentaurWeb.Sample",
        consumer: "MediaCentaurWeb.Sample",
        file: "lib/sample.ex",
        line: 7,
        excerpt: "def sample(:ignored), do: :hidden"
      })

    second_site = %{second | line: 9, excerpt: "def other(:ignored), do: :shown"}
    html = Html.render(%{@document | findings: [first, second, second_site]})

    assert [concept] = html |> query(".concept") |> Enum.to_list()
    assert LazyHTML.attribute(concept, "data-concept") == [first.concept_key]

    consumers = LazyHTML.query(concept, ".consumer")
    assert Enum.count(consumers) == 2

    sample = Enum.to_list(LazyHTML.query(concept, ~s(.consumer[data-key="#{second.key}"] .finding)))

    assert length(sample) == 2
    excerpts = concept |> LazyHTML.query(".excerpt") |> Enum.map(&LazyHTML.text/1)

    assert excerpts == [
             first.excerpt,
             "def sample(:ignored), do: :hidden",
             "def other(:ignored), do: :shown"
           ]

    assert concept |> LazyHTML.query(".concept-head") |> LazyHTML.text() =~ "2 consumers · 3 sites"
  end

  test "escapes excerpts" do
    finding = Map.put(hd(@document.findings), :excerpt, "<script>x</script>")
    html = Html.render(%{@document | findings: [finding]})
    assert html =~ "&lt;script&gt;x&lt;/script&gt;"
    refute html =~ "<script>x</script>"
  end

  test "escapes rule, line and anchored" do
    finding = Map.merge(hd(@document.findings), %{rule: "R<9>", line: "<1>", anchored: "<a>"})
    html = Html.render(%{@document | findings: [finding]})
    refute html =~ "R<9>"
    refute html =~ "<1>"
    refute html =~ "<a>"
  end
end
