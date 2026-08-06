defmodule MediaCentaur.Credo.Checks.ArtworkWidthDeclaredTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.ArtworkWidthDeclared

  defp component(body) do
    """
    defmodule MediaCentaurWeb.Components.Sample do
      use Phoenix.Component

      def card(assigns) do
        ~H\"\"\"
    #{body}
        \"\"\"
      end
    end
    """
  end

  defp check(body, path \\ "lib/media_centaur_web/components/sample.ex") do
    body |> component() |> to_source_file(path) |> run_check(ArtworkWidthDeclared)
  end

  describe "violations" do
    test "flags a backdrop rendered without a declared width" do
      ~S|      <img src={@item.backdrop_url} />|
      |> check()
      |> assert_issue()
    end

    test "flags a logo rendered without a declared width" do
      ~S|      <img src={@item.logo_url} alt={@item.name} />|
      |> check()
      |> assert_issue()
    end

    test "flags a poster rendered without a declared width" do
      ~S|      <img src={entry.poster_url} />|
      |> check()
      |> assert_issue()
    end

    test "flags artwork built through Image.web_path/1" do
      ~S|      <img src={MediaCentaur.Library.Image.web_path(@detail.backdrop_path)} />|
      |> check()
      |> assert_issue()
    end

    test "flags each undeclared image separately" do
      """
            <img src={@item.backdrop_url} />
            <img src={@item.logo_url} />
      """
      |> check()
      |> assert_issues(&(length(&1) == 2))
    end
  end

  describe "clean code" do
    test "allows an explicit pixel width" do
      ~S|      <img src={sized_image_url(@item.backdrop_url, 1280)} />|
      |> check()
      |> refute_issues()
    end

    test "allows an explicit :full_bleed declaration" do
      ~S|      <img src={sized_image_url(@hero.backdrop_url, :full_bleed)} />|
      |> check()
      |> refute_issues()
    end

    # A surface may own its `src` builder so `ArtworkWarmup` can call the same
    # function — `LibraryCards.poster_src/1` is the worked example. The width
    # is declared inside that function, where the check still sees it.
    test "allows a named src builder that ends in _src" do
      ~S|      <img src={poster_src(@entry.poster_url)} />|
      |> check()
      |> refute_issues()
    end

    # ImageServer can only resize what it serves; a remote TMDB URL already
    # names its size in the path (`/t/p/w92/...`).
    test "ignores remote TMDB URLs, which carry their size in the path" do
      ~S|      <img src={"https://image.tmdb.org/t/p/w92#{@result.poster_path}"} />|
      |> check()
      |> refute_issues()
    end

    test "ignores non-artwork images" do
      ~S|      <img src={~p"/images/logo.svg"} />|
      |> check()
      |> refute_issues()
    end

    test "ignores files outside the web layer" do
      ~S|      <img src={@item.backdrop_url} />|
      |> check("lib/media_centaur/some_context.ex")
      |> refute_issues()
    end
  end
end
