defmodule MediaCentaur.ContextMap.SourcesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Source
  alias MediaCentaur.ContextMap.Sources

  @code """
  defmodule MediaCentaurWeb.SampleLive do
    use MediaCentaurWeb, :live_view
    alias MediaCentaur.Discovery.TitleIntent
    alias MediaCentaurWeb.Components.Title.{Logic, Row}
    alias MediaCentaur.Library.Movie, as: Film

    def pick(%TitleIntent{rung: rung}), do: Logic.marker(rung)
    def film(%Film{} = film), do: Row.render(film)
  end
  """

  test "modules, context, resolved references, live_view flag" do
    source = Sources.parse("lib/media_centaur_web/live/sample_live.ex", @code)

    assert %Source{
             path: "lib/media_centaur_web/live/sample_live.ex",
             modules: [MediaCentaurWeb.SampleLive],
             context: :web,
             live_view?: true
           } = source

    assert MediaCentaur.Discovery.TitleIntent in source.references
    assert MediaCentaurWeb.Components.Title.Logic in source.references
    assert MediaCentaurWeb.Components.Title.Row in source.references
    assert MediaCentaur.Library.Movie in source.references
    assert Enum.at(source.lines, 1) =~ "live_view"
  end

  test "a context module is not a live view and has its context" do
    source =
      Sources.parse(
        "lib/media_centaur/discovery.ex",
        "defmodule MediaCentaur.Discovery do\n  def x, do: 1\nend\n"
      )

    assert %Source{context: MediaCentaur.Discovery, live_view?: false} = source
  end

  test "alias __MODULE__.Child resolves against the file's first module" do
    code = """
    defmodule MediaCentaur.Sample do
      alias __MODULE__.Child
      def x, do: Child.y()
    end
    """

    source = Sources.parse("lib/media_centaur/sample.ex", code)
    assert MediaCentaur.Sample.Child in source.references
  end

  test "all/0 reads every .ex under lib/media_centaur and lib/media_centaur_web, nothing under lib/mix" do
    paths = Enum.map(Sources.all(), & &1.path)
    assert "lib/media_centaur/discovery.ex" in paths
    assert "lib/media_centaur_web/components/title/logic.ex" in paths
    refute Enum.any?(paths, &String.starts_with?(&1, "lib/mix/"))
    assert paths == Enum.sort(paths)
  end

  test "line/2 is the text of a 1-based line, empty past the end" do
    source =
      Sources.parse(
        "lib/media_centaur/sample.ex",
        "defmodule MediaCentaur.Sample do\n  def f, do: :ok\nend\n"
      )

    assert Source.line(source, 2) == "  def f, do: :ok"
    assert Source.line(source, 99) == ""
  end
end
