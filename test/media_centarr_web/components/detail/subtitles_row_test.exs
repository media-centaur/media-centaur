defmodule MediaCentarrWeb.Components.Detail.SubtitlesRowTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.Detail.SubtitlesRow

  defp render_row(languages) do
    render_component(&SubtitlesRow.subtitles_row/1, %{languages: languages})
  end

  test "renders nothing when the languages list is empty" do
    html = render_row([])
    refute html =~ "Subtitles"
    refute html =~ "external"
  end

  test "renders a single language without a separator" do
    html = render_row(["en"])
    assert html =~ "Subtitles"
    assert html =~ "en"
    refute html =~ "·"
  end

  test "renders multiple languages separated by middle dots" do
    html = render_row(["en", "es", "fr"])
    assert html =~ "en"
    assert html =~ "es"
    assert html =~ "fr"
    assert html =~ "·"
  end

  test "renders nil as 'external'" do
    html = render_row([nil])
    assert html =~ "Subtitles"
    assert html =~ "external"
  end

  test "renders a mix of known languages and 'external'" do
    html = render_row(["en", nil])
    assert html =~ "en"
    assert html =~ "external"
  end
end
