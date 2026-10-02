defmodule MediaCentaurWeb.Components.Social.HueSwatchesTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaurWeb.Components.Social.HueSwatches

  defp render(attrs) do
    LazyHTML.from_fragment(
      render_component(&HueSwatches.hue_swatches/1, Map.merge(%{id: "hues", event: "pick"}, attrs))
    )
  end

  defp swatches(html), do: LazyHTML.query(html, "[data-component='hue-swatches'] button[data-hue]")

  test "eight palette swatches, each a nav item pushing the event with its hue and the caller's values; the chosen one is pressed" do
    html = render(%{selected: 195, values: %{"pubkey" => "abc"}})
    swatches = swatches(html)

    assert Enum.count(swatches) == 8
    assert Enum.uniq(LazyHTML.attribute(swatches, "phx-click")) == ["pick"]
    assert Enum.uniq(LazyHTML.attribute(swatches, "phx-value-pubkey")) == ["abc"]
    assert LazyHTML.attribute(swatches, "phx-value-hue") == ~w(12 45 80 150 195 250 290 335)
    assert hd(LazyHTML.attribute(swatches, "style")) == "--hue: 12"
    assert hd(LazyHTML.attribute(swatches, "aria-label")) == "Rose"
    assert length(LazyHTML.attribute(swatches, "data-nav-item")) == 8

    assert html |> LazyHTML.query("[data-component='hue-swatches']") |> LazyHTML.attribute("role") ==
             ["group"]

    pressed = LazyHTML.query(html, "button[data-hue][aria-pressed='true']")
    assert LazyHTML.attribute(pressed, "data-hue") == ["195"]
  end

  test "the slider is a form field named hue at the chosen angle, with the ring as its track" do
    slider = LazyHTML.query(render(%{selected: 195}), "input[type='range'][name='hue']")
    assert LazyHTML.attribute(slider, "value") == ["195"]
    assert LazyHTML.attribute(slider, "min") == ["0"]
    assert LazyHTML.attribute(slider, "max") == ["359"]
    assert LazyHTML.attribute(slider, "aria-label") == ["Any colour"]
    assert LazyHTML.attribute(slider, "phx-debounce") == ["150"]
    refute Enum.any?(LazyHTML.query(render(%{selected: 195}), "form"))
  end

  test "Theirs leads the row when asked, in the published hue, pushing an empty hue; pressed when nothing is chosen" do
    html = render(%{selected: nil, theirs?: true, theirs_hue: 12})
    theirs = LazyHTML.query(html, "button[data-role='theirs']")
    assert LazyHTML.attribute(theirs, "aria-pressed") == ["true"]
    assert LazyHTML.attribute(theirs, "phx-value-hue") == [""]
    assert LazyHTML.attribute(theirs, "style") == ["--hue: 12"]
    assert LazyHTML.attribute(theirs, "aria-label") == ["Theirs"]
    assert html |> LazyHTML.query("input[type='range']") |> LazyHTML.attribute("value") == ["12"]

    overridden = render(%{selected: 195, theirs?: true, theirs_hue: 12})

    assert overridden
           |> LazyHTML.query("button[data-role='theirs']")
           |> LazyHTML.attribute("aria-pressed") == ["false"]

    no_published = render(%{selected: nil, theirs?: true, theirs_hue: nil})

    assert no_published |> LazyHTML.query("button[data-role='theirs']") |> LazyHTML.attribute("style") ==
             []

    assert no_published |> LazyHTML.query("input[type='range']") |> LazyHTML.attribute("value") == [
             "250"
           ]

    refute render(%{selected: 195}) |> LazyHTML.query("button[data-role='theirs']") |> Enum.any?()
  end
end
