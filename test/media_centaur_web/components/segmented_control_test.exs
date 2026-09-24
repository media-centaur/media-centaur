defmodule MediaCentaurWeb.Components.SegmentedControlTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaurWeb.CoreComponents

  @options [{:everyone, "Everyone"}, {:friends, "Friends"}, {:you, "You"}]

  defp render(overrides) do
    attrs =
      Keyword.merge(
        [label: "Scope", options: @options, selected: :friends, event: "pick"],
        overrides
      )

    render_component(&CoreComponents.segmented_control/1, attrs)
  end

  defp buttons(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.query("button.tab")

  test "one button per option carrying the event and its value as choice; only the chosen one is pressed" do
    buttons = buttons(render([]))

    assert LazyHTML.attribute(buttons, "phx-click") == ["pick", "pick", "pick"]
    assert LazyHTML.attribute(buttons, "phx-value-choice") == ["everyone", "friends", "you"]
    assert LazyHTML.attribute(buttons, "aria-pressed") == ["false", "true", "false"]
    assert Enum.map(buttons, &(&1 |> LazyHTML.text() |> String.trim())) == ["Everyone", "Friends", "You"]
  end

  test "the group carries its accessible name and extra event params reach every button" do
    html = render(id: "scope", event_value: %{"id" => "chart"})
    group = html |> LazyHTML.from_fragment() |> LazyHTML.query("#scope[role='group']")

    assert LazyHTML.attribute(group, "aria-label") == ["Scope"]
    assert html |> buttons() |> LazyHTML.attribute("phx-value-id") == ["chart", "chart", "chart"]
  end

  test "every option is a nav item; whether it is reachable is its zone's decision" do
    assert render([]) |> buttons() |> LazyHTML.attribute("data-nav-item") |> length() == 3
    assert render([]) |> buttons() |> LazyHTML.attribute("tabindex") == ["0", "0", "0"]
  end

  test "an event param named value is refused: a button's native value clobbers it on click" do
    assert_raise ArgumentError, ~r/phx-value-value/, fn ->
      render(event_value: %{"value" => "x"})
    end
  end
end
