defmodule MediaCentaurWeb.Components.GlassMenu do
  @moduledoc """
  The house dropdown idiom (`.glass-menu*` in `app.css`): a trigger with a
  chevron and an anchored glass list beneath it, open state owned by the
  LiveView. Three components: `menu_list/1` is the list; `split_button/1`
  puts it under a two-segment trigger whose main segment performs an
  action; `menu_select/1` under a trigger that shows the current value.
  The tenants are the title detail modal's Download control and scope
  select, and the library sort control (spec 2026-09-12 §12–16).

  ## Nav

  The list is its own nav zone (`zone` / `menu_zone`) inside the
  trigger's zone — nesting the input system allows because an item
  counts for its nearest zone only — and declares
  `data-nav-dismiss-event`, so BACK along the zone's `back` edge returns
  the cursor to the trigger and asks the LiveView to close the list in
  one press. The tenant's layout in `config.js` declares the zone: a
  TREE reached by DOWN from the trigger's zone, with `up` and `back`
  edges to it.

  ## Open state

  `open` is the host's assign. `on_toggle` is what the trigger pushes
  (an event name or a `JS.push/2` carrying a value); `on_close` is a
  plain event name, pushed by a click outside (`phx-click-away`) and by
  BACK. The host closes the list itself when an item's event lands.
  """

  use MediaCentaurWeb, :html

  @variants ~w(primary secondary action info risky danger dismiss destructive_inline neutral outline)

  attr :id, :string, required: true
  attr :zone, :string, required: true, doc: "the list's `data-nav-zone` — a TREE declared in `config.js`"
  attr :on_close, :string, required: true, doc: "the event BACK pushes when it leaves the list"
  attr :class, :any, default: nil, doc: "utilities on the `ul`"

  slot :item, required: true do
    attr :id, :string
    attr :event, :string, required: true
    attr :values, :map, doc: "`phx-value-*` params, string-keyed"
    attr :active, :boolean, doc: "the current choice (`menu_select`)"
  end

  def menu_list(assigns) do
    ~H"""
    <ul
      id={@id}
      class={["glass-menu-list glass-surface", @class]}
      role="menu"
      data-nav-zone={@zone}
      data-nav-dismiss-event={@on_close}
    >
      <li
        :for={item <- @item}
        id={item[:id]}
        role="menuitem"
        class={["glass-menu-item", item[:active] && "glass-menu-item-active"]}
        phx-click={item.event}
        {phx_values(item[:values])}
        data-nav-item
        tabindex="0"
      >
        {render_slot(item)}
      </li>
    </ul>
    """
  end

  attr :id, :string,
    required: true,
    doc: "the main segment's id; the chevron is `<id>-toggle`, the list `<id>-menu`"

  attr :open, :boolean, required: true
  attr :on_toggle, :any, required: true, doc: "event name or `Phoenix.LiveView.JS` the chevron pushes"
  attr :on_close, :string, required: true, doc: "the event a click outside and BACK push"
  attr :menu_zone, :string, required: true, doc: "the list's `data-nav-zone`"
  attr :variant, :string, default: "primary", values: @variants
  attr :size, :string, default: "sm", values: ~w(xs sm md lg)
  attr :menu_label, :string, default: "More options", doc: "the chevron's accessible name"
  attr :disabled, :boolean, default: false
  attr :class, :any, default: nil, doc: "utilities on the wrapper"
  attr :rest, :global, doc: "the main segment's bindings: `phx-click`, `phx-value-*`"

  slot :inner_block, required: true, doc: "the main segment's label"

  slot :item, required: true do
    attr :id, :string
    attr :event, :string, required: true
    attr :values, :map, doc: "`phx-value-*` params, string-keyed"
    attr :active, :boolean
  end

  def split_button(assigns) do
    assigns = assign(assigns, :divider, divider_class(assigns.variant))

    ~H"""
    <span id={@id <> "-split"} class={["glass-menu inline-flex", @class]} phx-click-away={@on_close}>
      <.button
        id={@id}
        variant={@variant}
        size={@size}
        class="rounded-r-none"
        disabled={@disabled}
        data-nav-item
        tabindex="0"
        {@rest}
      >
        {render_slot(@inner_block)}
      </.button>
      <.button
        id={@id <> "-toggle"}
        variant={@variant}
        size={@size}
        shape="square"
        class={["rounded-l-none border-l", @divider]}
        disabled={@disabled}
        phx-click={@on_toggle}
        aria-label={@menu_label}
        aria-haspopup="menu"
        aria-expanded={to_string(@open)}
        data-nav-item
        tabindex="0"
      >
        <span class={["glass-menu-chevron", @open && "rotate-180"]}>
          <.icon name="hero-chevron-down-mini" class="size-4" />
        </span>
      </.button>
      <.menu_list
        :if={@open}
        id={@id <> "-menu"}
        zone={@menu_zone}
        on_close={@on_close}
        class="glass-menu-list--content"
      >
        <:item
          :for={item <- @item}
          id={item[:id]}
          event={item.event}
          values={item[:values]}
          active={item[:active]}
        >
          {render_slot(item)}
        </:item>
      </.menu_list>
    </span>
    """
  end

  attr :id, :string, required: true, doc: "the trigger's id; the list is `<id>-menu`"
  attr :open, :boolean, required: true
  attr :on_toggle, :any, required: true, doc: "event name or `Phoenix.LiveView.JS` the trigger pushes"
  attr :on_close, :string, required: true, doc: "the event a click outside and BACK push"
  attr :menu_zone, :string, required: true, doc: "the list's `data-nav-zone`"
  attr :value_label, :string, required: true, doc: "the trigger's text — the current choice"
  attr :label, :string, required: true, doc: ~s(the accessible name, e.g. "Sort" or "Download scope")
  attr :class, :any, default: nil, doc: "utilities on the wrapper"
  attr :rest, :global, doc: "data attributes on the wrapper (`data-sort`)"

  slot :item, required: true do
    attr :id, :string
    attr :event, :string, required: true
    attr :values, :map, doc: "`phx-value-*` params, string-keyed"
    attr :active, :boolean, doc: "the current choice"
  end

  def menu_select(assigns) do
    ~H"""
    <span
      id={@id <> "-select"}
      class={["glass-menu inline-flex", @class]}
      phx-click-away={@on_close}
      {@rest}
    >
      <button
        id={@id}
        type="button"
        class="glass-menu-trigger"
        phx-click={@on_toggle}
        aria-label={@label}
        aria-haspopup="menu"
        aria-expanded={to_string(@open)}
        data-nav-item
        tabindex="0"
      >
        {@value_label}
        <span class={["glass-menu-chevron", @open && "rotate-180"]}>
          <.icon name="hero-chevron-down-mini" class="size-4" />
        </span>
      </button>
      <.menu_list :if={@open} id={@id <> "-menu"} zone={@menu_zone} on_close={@on_close}>
        <:item
          :for={item <- @item}
          id={item[:id]}
          event={item.event}
          values={item[:values]}
          active={item[:active]}
        >
          {render_slot(item)}
        </:item>
      </.menu_list>
    </span>
    """
  end

  # The hairline between the segments takes the variant's own ink so it
  # reads on a solid primary and on a soft tint alike.
  defp divider_class("primary"), do: "border-primary-content/20"
  defp divider_class(_variant), do: "border-base-content/15"

  # `phx-value-<key>` per entry; MC0021 forbids the key `value` itself.
  defp phx_values(nil), do: %{}
  defp phx_values(map), do: Map.new(map, fn {key, value} -> {"phx-value-#{key}", value} end)
end
