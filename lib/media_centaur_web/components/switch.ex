defmodule MediaCentaurWeb.Components.Switch do
  @moduledoc """
  The app's one switch: a toggle glyph and its words, the whole thing one
  click (`role="switch"`, `aria-checked`). The row is the control — the
  checkbox inside takes no pointer and no focus — so a click anywhere on
  it pushes `event` with `values` as its `phx-value-*` params, and the
  nav graph sees one item (`data-nav-item`).

  **Held** — `event` nil: no click, `aria-disabled="true"`, dimmed
  (`opacity-60`), and the description says why. It keeps its place so the
  nav graph never shifts under focus.

  Two layouts. `:leading` puts the toggle before the words, compact
  (`text-sm`), for a switch inside a card or a block: the tracking block's
  Track release dates and Auto-grab (`Title.TrackingControls`) and the person card's
  *Show their picture* (`Discovery.PersonCard`). `:trailing` puts the
  words first at the Settings kit's size and the toggle right-aligned: the
  Settings row (`Settings.settings_row/1`). The caller sets the row's
  spacing through `class`.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [phx_values: 1]

  attr :id, :string, default: nil

  attr :label, :string, required: true

  attr :description, :string, default: nil
  attr :checked, :boolean, required: true

  attr :event, :string,
    default: nil,
    doc: "the click's event; nil holds the switch: no click, aria-disabled, and the description says why"

  attr :values, :map, default: %{}, doc: "phx-value-* params, string-keyed; a nil value is dropped"

  attr :layout, :atom,
    values: [:leading, :trailing],
    default: :leading,
    doc:
      "the toggle before the words (a card, the tracking block) or after them, right-aligned (a Settings row)"

  attr :class, :any, default: nil, doc: "the row's spacing; the Settings row sets its own"
  attr :rest, :global, doc: "`data-*` markers a host or a test reads the switch by"

  def switch(assigns) do
    ~H"""
    <div
      id={@id}
      role="switch"
      aria-checked={to_string(@checked)}
      aria-disabled={is_nil(@event) && "true"}
      class={[
        "flex gap-3 rounded-lg transition-colors duration-150",
        if(@layout == :leading and @description, do: "items-start", else: "items-center"),
        @layout == :trailing && "justify-between",
        if(@event, do: "cursor-pointer hover:bg-base-content/[0.04]", else: "opacity-60"),
        @class
      ]}
      data-nav-item
      tabindex="0"
      phx-click={@event}
      {phx_values(@values)}
      {@rest}
    >
      <.toggle :if={@layout == :leading} checked={@checked} class={@description && "mt-0.5"} />
      <span class="min-w-0">
        <span class={label_class(@layout, @description)}>{@label}</span>
        <span :if={@description} class={description_class(@layout)}>{@description}</span>
      </span>
      <.toggle :if={@layout == :trailing} checked={@checked} />
    </div>
    """
  end

  attr :checked, :boolean, required: true
  attr :class, :string, default: nil

  # The glyph. It takes no pointer and no focus: the row is the control.
  defp toggle(assigns) do
    ~H"""
    <input
      type="checkbox"
      class={["toggle toggle-sm toggle-info pointer-events-none", @class]}
      checked={@checked}
      tabindex="-1"
    />
    """
  end

  # The words: the Settings kit's size for a row, compact for a switch
  # inside a card or a block.
  defp label_class(:trailing, _description), do: "block font-medium"
  defp label_class(:leading, nil), do: "block text-sm"
  defp label_class(:leading, _description), do: "block text-sm font-medium leading-tight"

  defp description_class(:trailing), do: "block text-xs text-base-content/55 mt-0.5"
  defp description_class(:leading), do: "block text-xs text-base-content/55"
end
