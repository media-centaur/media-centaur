defmodule MediaCentaurWeb.Components.SidebarLinkTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaurWeb.Components.SidebarLink

  @base [id: "sidebar-sample", navigate: "/sample", label: "Sample", icon: "hero-home"]

  defp render(attrs),
    do:
      LazyHTML.from_fragment(render_component(&SidebarLink.sidebar_link/1, Keyword.merge(@base, attrs)))

  defp count(html, selector), do: html |> LazyHTML.query(selector) |> Enum.count()

  test "an entry is an icon-only link named and tipped by its label, a nav item" do
    html = render([])

    assert count(
             html,
             "a#sidebar-sample.sidebar-link[href='/sample'][aria-label='Sample'][data-tip='Sample']"
           ) == 1

    assert count(html, "a#sidebar-sample[data-nav-item][tabindex='0']") == 1
    assert count(html, "a#sidebar-sample .hero-home") == 1
    assert count(html, "a#sidebar-sample[aria-current]") == 0
    assert count(html, "a#sidebar-sample[data-nav-remember]") == 0
    assert count(html, "a#sidebar-sample.sidebar-link-system") == 0
  end

  test "the active entry is the current page" do
    html = render(active: true)
    assert count(html, "a#sidebar-sample.sidebar-link-active[aria-current='page']") == 1
  end

  test "a System entry is marked, and a remembered one keeps the page's URL" do
    html = render(system: true, remember: true)
    assert count(html, "a#sidebar-sample.sidebar-link-system[data-nav-remember]") == 1
  end

  test "a count draws the follow-up pill; zero draws nothing" do
    html = render(count: 3)

    assert html
           |> LazyHTML.query("#sidebar-sample-follow-up[data-component='follow-up-pill']")
           |> LazyHTML.text()
           |> String.trim() == "3"

    assert count(render(count: 0), "[data-component='follow-up-pill']") == 0
  end

  test "a condition draws the dot at the icon" do
    assert count(render(condition: true), "#sidebar-sample-condition-dot") == 1
    assert count(render([]), "#sidebar-sample-condition-dot") == 0
  end

  test "a hue makes the entry a person's, carrying the hue for its accent" do
    html = render(hue: 150)
    assert count(html, "a#sidebar-sample.sidebar-link-profile[data-hue='150'][style='--hue: 150']") == 1
    assert count(render([]), "a#sidebar-sample.sidebar-link-profile") == 0
  end
end
