defmodule MediaCentaurWeb.Components.TabStripTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MediaCentaurWeb.Components.TabStrip
  alias MediaCentaurWeb.Components.TabStrip.Tab

  defp tabs do
    [
      %Tab{id: :first, label: "First", navigate: "/first", count: 3},
      %Tab{id: :second, label: "Second", navigate: "/second"}
    ]
  end

  test "renders one link per tab, marks the active one, and badges non-zero counts" do
    html = render_component(&TabStrip.tab_strip/1, tabs: tabs(), active: :second)

    assert html =~ ~s(href="/first")
    assert html =~ ~s(href="/second")
    assert html =~ "First"
    assert html =~ "Second"
    # the count badge renders only for the tab that has work
    assert html =~ ~r/>\s*3\s*</
    # exactly one active tab, and it is the one asked for
    assert [active] = select(html, ".zone-tab-active")
    assert LazyHTML.text(active) =~ "Second"
  end

  test "the strip is one zone-tabs nav zone of nav items" do
    html = render_component(&TabStrip.tab_strip/1, tabs: tabs(), active: :first)

    assert length(select(html, "[data-nav-zone='zone-tabs']")) == 1
    assert length(select(html, "[data-nav-zone='zone-tabs'] [data-nav-item]")) == 2
  end

  # A function component has no LiveView to `has_element?/2` against, so
  # parse the fragment the way the element API does (LazyHTML) instead of
  # substring-matching attributes (MC0024).
  defp select(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.to_list()
  end
end
