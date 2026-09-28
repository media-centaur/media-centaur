defmodule MediaCentaurWeb.Components.Discovery.HueSwatches do
  @moduledoc """
  The one place a hue is chosen (UIDR-048): the palette as round
  swatches in ring order, the chosen one pressed, and under them the
  ring itself as a slider, its thumb at the chosen angle. A swatch is a
  button pushing `event` with the caller's `values` and `hue`; the
  slider is a form field named `hue` and carries no event of its own —
  the host's enclosing form's `phx-change` receives it (Settings' profile
  form; a small `set_hue_override` form on a friend's card foot), so a
  click and a drag reach one handler with one payload. Every swatch and
  the slider are nav items.

  `theirs?` leads the row with **Theirs**, the friend's published hue
  (`theirs_hue`; the default Blue when nil), pressed while `selected` is
  nil and pushing an empty `hue` to clear the override.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [phx_values: 1]

  alias MediaCentaur.Social.Hue

  attr :id, :string, required: true
  attr :selected, :integer, default: nil, doc: "the chosen hue; nil is none (Theirs, when shown)"
  attr :theirs?, :boolean, default: false, doc: "lead with the friend's published hue"
  attr :theirs_hue, :integer, default: nil, doc: "the published hue Theirs draws; nil draws the default"
  attr :event, :string, required: true, doc: "pushed by a swatch with `values` and `hue`"
  attr :values, :map, default: %{}, doc: "phx-value-* params a swatch carries beside `hue`"
  attr :class, :any, default: nil
  attr :rest, :global

  def hue_swatches(assigns) do
    assigns = assign(assigns, thumb: assigns.selected || assigns.theirs_hue || 250)

    ~H"""
    <div id={@id} class={["space-y-2", @class]} data-component="hue-swatches" {@rest}>
      <div class="flex flex-wrap items-center gap-2.5">
        <button
          :if={@theirs?}
          type="button"
          class="hue-swatch"
          {theirs_style(@theirs_hue)}
          aria-pressed={to_string(is_nil(@selected))}
          aria-label="Theirs"
          title="Theirs"
          phx-click={@event}
          {phx_values(Map.put(@values, "hue", ""))}
          data-role="theirs"
          data-nav-item
          tabindex="0"
        ></button>
        <button
          :for={{name, hue} <- Hue.palette()}
          type="button"
          class="hue-swatch"
          style={"--hue: #{hue}"}
          aria-pressed={to_string(@selected == hue)}
          aria-label={name}
          title={name}
          phx-click={@event}
          {phx_values(Map.put(@values, "hue", hue))}
          data-hue={hue}
          data-nav-item
          tabindex="0"
        ></button>
      </div>
      <input
        type="range"
        name="hue"
        min="0"
        max="359"
        value={@thumb}
        class="hue-slider"
        aria-label="Any colour"
        phx-debounce="150"
        data-nav-item
        tabindex="0"
      />
    </div>
    """
  end

  # Theirs with no published hue carries no `style` at all, so the CSS
  # default draws it. A `style={…}` of nil, or a literal spread of one,
  # still renders `style=""` — HEEx treats `style` like `class` — so the
  # attribute list is built here and spread at runtime, which drops nil.
  defp theirs_style(nil), do: []
  defp theirs_style(hue), do: [style: "--hue: #{hue}"]
end
