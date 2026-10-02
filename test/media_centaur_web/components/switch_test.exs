defmodule MediaCentaurWeb.Components.SwitchTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaurWeb.Components.Switch

  defp render(attrs) do
    html = render_component(&Switch.switch/1, attrs)
    html |> LazyHTML.from_fragment() |> LazyHTML.query("[role='switch']")
  end

  defp tracking_row(overrides) do
    Keyword.merge(
      [
        id: "switch-track",
        label: "Track release dates",
        description: "Its new episodes, as TMDB posts their air dates.",
        checked: false,
        event: "set_rung",
        values: %{"choice" => "follow", "ref" => "tv_series-1399"}
      ],
      overrides
    )
  end

  test "the row is the control: it carries the role, the state, the click and its values; the checkbox is inert" do
    switch = render(tracking_row([]))

    assert LazyHTML.attribute(switch, "id") == ["switch-track"]
    assert LazyHTML.attribute(switch, "aria-checked") == ["false"]
    assert LazyHTML.attribute(switch, "aria-disabled") == []
    assert LazyHTML.attribute(switch, "tabindex") == ["0"]
    assert LazyHTML.attribute(switch, "data-nav-item") == [""]
    assert LazyHTML.attribute(switch, "phx-click") == ["set_rung"]
    assert LazyHTML.attribute(switch, "phx-value-choice") == ["follow"]
    assert LazyHTML.attribute(switch, "phx-value-ref") == ["tv_series-1399"]

    checkbox = LazyHTML.query(switch, "input[type='checkbox']")
    assert LazyHTML.attribute(checkbox, "tabindex") == ["-1"]
    assert LazyHTML.attribute(checkbox, "checked") == []

    assert LazyHTML.text(switch) =~ "Its new episodes"
  end

  test "checked: the state and the checkbox agree" do
    switch = render(tracking_row(checked: true))

    assert LazyHTML.attribute(switch, "aria-checked") == ["true"]
    assert switch |> LazyHTML.query("input[type='checkbox']") |> LazyHTML.attribute("checked") == [""]
  end

  test "held: no event is no click and aria-disabled; a nil value emits no param, the rest stay" do
    switch = render(tracking_row(event: nil, values: %{"choice" => nil, "ref" => "tv_series-1399"}))

    assert LazyHTML.attribute(switch, "phx-click") == []
    assert LazyHTML.attribute(switch, "aria-disabled") == ["true"]
    assert LazyHTML.attribute(switch, "phx-value-choice") == []
    assert LazyHTML.attribute(switch, "phx-value-ref") == ["tv_series-1399"]
  end

  test "leading puts the toggle before the words; trailing puts it after them" do
    leading = render(tracking_row([]))
    assert leading |> LazyHTML.query("[role='switch'] > :first-child") |> LazyHTML.tag() == ["input"]
    assert leading |> LazyHTML.query("[role='switch'] > :last-child") |> LazyHTML.tag() == ["span"]

    trailing = render(tracking_row(layout: :trailing))
    assert trailing |> LazyHTML.query("[role='switch'] > :first-child") |> LazyHTML.tag() == ["span"]
    assert trailing |> LazyHTML.query("[role='switch'] > :last-child") |> LazyHTML.tag() == ["input"]
  end

  test "a label alone is one line; a description adds a second" do
    label_only = render(tracking_row(description: nil))
    assert label_only |> LazyHTML.query("[role='switch'] > span > span") |> Enum.count() == 1

    described = render(tracking_row([]))
    assert described |> LazyHTML.query("[role='switch'] > span > span") |> Enum.count() == 2
  end

  test "the id is omitted when none is given; data markers pass through" do
    switch =
      render(
        label: "Show their picture",
        checked: true,
        event: "set_show_avatar",
        values: %{"pubkey" => "f9308a01", "show" => "false"},
        "data-role": "avatar-switch"
      )

    assert LazyHTML.attribute(switch, "id") == []
    assert LazyHTML.attribute(switch, "data-role") == ["avatar-switch"]
    assert LazyHTML.attribute(switch, "phx-value-show") == ["false"]
  end
end
