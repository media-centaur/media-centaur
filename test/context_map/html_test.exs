defmodule MediaCentaur.ContextMap.HtmlTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Html

  @document %{
    contexts: [
      %{
        name: "MediaCentaur.Watchlist",
        kernel: false,
        deps: ["MediaCentaur.Library"],
        exports: ["MediaCentaur.Watchlist.TitleIntent"],
        schemas: [
          %{
            module: "MediaCentaur.Watchlist.TitleIntent",
            table: "title_intents",
            fields: [
              %{
                name: "rung",
                type: "Ecto.Enum",
                values: ["ignored", "list"],
                reads: %{"MediaCentaur.Watchlist" => 2, "web" => 3},
                writes: %{"MediaCentaur.Watchlist" => 1}
              }
            ],
            associations: [
              %{
                name: "sample_parent",
                kind: "belongs_to",
                target: "MediaCentaur.Watchlist.SampleParent",
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
        owner: "MediaCentaur.Watchlist",
        schema: "MediaCentaur.Watchlist.TitleIntent",
        field: "tmdb_id",
        target: "external"
      },
      %{
        owner: "MediaCentaur.Watchlist",
        schema: "MediaCentaur.Watchlist.TitleIntent",
        field: "movie_id",
        target: "MediaCentaur.Library.Movie"
      }
    ],
    findings: [
      %{
        key: "R3|MediaCentaur.Watchlist.TitleIntent|rung|ignored|MediaCentaurWeb.Components.Title.Logic",
        rule: "R3",
        owner: "MediaCentaur.Watchlist",
        schema: "MediaCentaur.Watchlist.TitleIntent",
        field: "rung",
        value: "ignored",
        consumer: "MediaCentaurWeb.Components.Title.Logic",
        consumer_context: "web",
        surfaces: ["MediaCentaurWeb.IncomingLive"],
        anchored: true,
        file: "lib/x.ex",
        line: 189,
        excerpt: ~s|defp rung_marker(:ignored), do: "Ignored"|,
        concept_key: "R3|MediaCentaur.Watchlist.TitleIntent|rung|ignored|*",
        detail: nil,
        verdict: nil,
        reason: nil,
        verdict_key: nil
      }
    ]
  }

  test "renders matrix, panels and findings with the finding key, and escapes" do
    html = Html.render(@document)

    assert html =~ "<title>Context map</title>"

    assert html =~
             "R3|MediaCentaur.Watchlist.TitleIntent|rung|ignored|MediaCentaurWeb.Components.Title.Logic"

    assert html |> query(~s(.panel[data-context="MediaCentaur.Watchlist"])) |> LazyHTML.text() =~
             "title_intents"

    assert html |> query(".consumer") |> LazyHTML.text() =~ "MediaCentaurWeb.IncomingLive"

    assert html
           |> LazyHTML.from_document()
           |> LazyHTML.query(~s([data-cell="MediaCentaur.Watchlist→web"]))
           |> Enum.count() == 1

    refute html =~ "<script src="
  end

  test "an association row shows its name, kind, target and foreign key" do
    html = Html.render(@document)

    for text <- [
          "sample_parent",
          "belongs_to",
          "MediaCentaur.Watchlist.SampleParent",
          "sample_parent_id"
        ] do
      assert html =~ text
    end
  end

  test "escapes reasons" do
    first = hd(@document.findings)
    finding = Map.merge(first, %{verdict: "leak", reason: "<b>x</b>", verdict_key: first.key})
    html = Html.render(%{@document | findings: [finding]})
    assert html =~ "&lt;b&gt;x&lt;/b&gt;"
    refute html =~ "<b>x</b>"
  end

  defp query(html, selector), do: html |> LazyHTML.from_document() |> LazyHTML.query(selector)

  test "a kernel read shades its owner→target-context cell with its count" do
    [cell] =
      @document
      |> Html.render()
      |> query(~s([data-cell="MediaCentaur.Watchlist→MediaCentaur.Library"]))
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
           |> query(~s(.finding[data-owner="MediaCentaur.Watchlist"][data-consumer="web"]))
           |> Enum.count() == 1

    assert html
           |> query(~s(td[data-owner="MediaCentaur.Watchlist"][data-consumer="web"]))
           |> Enum.count() == 1

    assert html
           |> query(~s(select[data-filter="owner"] option[value="MediaCentaur.Watchlist"]))
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
        key: "R3|MediaCentaur.Watchlist.TitleIntent|rung|ignored|MediaCentaurWeb.Sample",
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

  test "a verdict from the concept key shows on the concept; a consumer's exact verdict is marked as overriding it" do
    first = hd(@document.findings)

    covered =
      Map.merge(first, %{
        verdict: "leak",
        reason: "<every> consumer",
        verdict_key: first.concept_key
      })

    overriding =
      Map.merge(first, %{
        key: "R3|MediaCentaur.Watchlist.TitleIntent|rung|ignored|MediaCentaurWeb.Sample",
        consumer: "MediaCentaurWeb.Sample",
        verdict: "allowed",
        reason: "display only",
        verdict_key: "R3|MediaCentaur.Watchlist.TitleIntent|rung|ignored|MediaCentaurWeb.Sample"
      })

    html = Html.render(%{@document | findings: [covered, overriding]})

    concept_verdict = html |> query(".concept .concept-verdict") |> LazyHTML.text()
    assert concept_verdict =~ "concept verdict"
    assert concept_verdict =~ "<every> consumer"

    assert html |> query(~s(.consumer[data-key="#{overriding.key}"] .overrides)) |> Enum.count() == 1
    assert html |> query(~s(.consumer[data-key="#{covered.key}"] .overrides)) |> Enum.empty?()
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
