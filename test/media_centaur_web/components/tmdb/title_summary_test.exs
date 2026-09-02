defmodule MediaCentaurWeb.Components.TMDB.TitleSummaryTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.TMDB.TitleSummary

  defp title(overrides \\ %{}) do
    Title.new!(
      Map.merge(
        %{
          tmdb_id: 777,
          media_type: :movie,
          name: "Sample Movie",
          year: "2010",
          overview: "A sample overview."
        },
        overrides
      )
    )
  end

  test "renders name, quiet type/year text, and the overview" do
    html = render_component(&TitleSummary.title_summary/1, title: title(), poster_url: nil)

    assert html =~ "Sample Movie"
    assert html =~ "Movie"
    assert html =~ "2010"
    assert html =~ "A sample overview."
    assert html =~ "hero-film-mini"
  end

  test "a TV title shows the TV icon fallback and no year when absent" do
    html =
      render_component(&TitleSummary.title_summary/1,
        title: title(%{media_type: :tv_series, year: nil}),
        poster_url: nil
      )

    assert html =~ "hero-tv-mini"
    refute html =~ "· "
  end

  test "a poster url replaces the icon with an eager, sync image" do
    html =
      render_component(&TitleSummary.title_summary/1,
        title: title(),
        poster_url: "https://image.tmdb.org/t/p/w92/p.jpg"
      )

    assert html =~ ~s(src="https://image.tmdb.org/t/p/w92/p.jpg")
    assert html =~ ~s(loading="eager")
    assert html =~ ~s(decoding="sync")
    refute html =~ "hero-film-mini"
  end

  test "the secondary slot displaces the overview; markers render on the identity line" do
    assigns = %{title: title()}

    html =
      rendered_to_string(~H"""
      <MediaCentaurWeb.Components.TMDB.TitleSummary.title_summary title={@title} poster_url={nil}>
        <:markers><span>Tracked</span></:markers>
        <:secondary>Why it is here</:secondary>
      </MediaCentaurWeb.Components.TMDB.TitleSummary.title_summary>
      """)

    assert html =~ "Tracked"
    assert html =~ "Why it is here"
    refute html =~ "A sample overview."
  end
end
