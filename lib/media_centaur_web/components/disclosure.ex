defmodule MediaCentaurWeb.Components.Disclosure do
  @moduledoc """
  The one disclosure: a head that shows or hides a body, owned by the
  LiveView (WAI-ARIA disclosure pattern).

  The component draws the contract every disclosure shares: the group
  (`data-nav-group`, so TREE navigation's LEFT collapses it), a head button
  carrying `aria-expanded` and `aria-controls` with a caret that turns when
  open, and a body rendered only while open. The input system reads
  `aria-expanded` straight from the server's render, and a patch can never
  close what the user opened, because nothing but the LiveView holds the
  state.

  Two owners, one markup:

    * **The page's disclosure state** (`MediaCentaurWeb.Live.DisclosureState`)
      when nothing else reads it: `open={DisclosureState.open?(@disclosures, id)}`
      and the default `event`. The host writes no handler.
    * **The host** when another handler reads it (a season list, a pursuit
      group, the journal): the host passes its own `open` and `event`, and
      its `phx-value-*` go on the head through `rest`.

  `keep_body` renders a closed body `hidden` instead of not at all, for a
  body holding form fields that must still submit.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaurWeb.Live.DisclosureState

  attr :id, :string, required: true, doc: "the group's DOM id, and the page state's key."
  attr :open, :boolean, required: true
  attr :label, :string, default: nil, doc: "the head's text, when there is no `:head` slot."

  attr :variant, :atom,
    default: :quiet,
    values: [:quiet, :panel, :bare],
    doc:
      "`:quiet` a caret and a small muted label over an indented body (rare content); " <>
        "`:panel` an inset box whose head is its first row; `:bare` the host styles the head."

  attr :event, :string,
    default: "disclosure:toggle",
    doc: "the toggle event; the default is answered by `DisclosureState`."

  attr :target, :any, default: nil, doc: "`phx-target`, for a disclosure inside a LiveComponent."

  attr :nav, :atom,
    default: :item,
    values: [:item, :sub_item, :none],
    doc: "how the input system reaches the head."

  attr :keep_body, :boolean, default: false, doc: "render a closed body `hidden` (form fields)."
  attr :class, :any, default: nil, doc: "the group's layout utilities (margins)."
  attr :head_class, :any, default: nil, doc: "`:bare` only: the head's own styling."
  attr :body_class, :any, default: nil, doc: "`:bare` only: the body's own styling."
  attr :rest, :global, doc: "on the head: the host's `phx-value-*`."

  slot :head, doc: "the head's content, in place of `label`."
  slot :inner_block, required: true, doc: "the body."

  def disclosure(assigns) do
    assigns = assign(assigns, :hook_owned?, assigns.event == DisclosureState.event())

    ~H"""
    <div id={@id} data-nav-group class={[group_class(@variant), @class]}>
      <button
        type="button"
        id={"#{@id}-head"}
        class={["disclosure-head", head_class(@variant), @variant == :bare && @head_class]}
        aria-expanded={to_string(@open)}
        aria-controls={"#{@id}-body"}
        phx-click={@event}
        phx-value-id={@hook_owned? && @id}
        phx-target={@target}
        data-nav-item={@nav == :item}
        data-nav-sub-item={@nav == :sub_item}
        tabindex={@nav == :item && "0"}
        {@rest}
      >
        <.icon name="hero-chevron-right-mini" class="size-4 shrink-0 disclosure-caret" />
        <%= if @head != [] do %>
          {render_slot(@head)}
        <% else %>
          <span>{@label}</span>
        <% end %>
      </button>
      <div
        :if={@open or @keep_body}
        id={"#{@id}-body"}
        hidden={!@open}
        class={[body_class(@variant), @variant == :bare && @body_class]}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp group_class(:panel), do: "glass-inset rounded-xl"
  defp group_class(_variant), do: nil

  defp head_class(:quiet),
    do:
      "cursor-pointer select-none inline-flex items-center gap-1.5 text-xs " <>
        "text-base-content/55 hover:text-base-content/80 transition-colors"

  defp head_class(:panel),
    do:
      "cursor-pointer select-none flex w-full items-center gap-1.5 px-4 py-3 text-sm " <>
        "text-base-content/60 hover:text-base-content/80 transition-colors"

  defp head_class(:bare), do: "cursor-pointer select-none"

  defp body_class(:quiet), do: "mt-3 ml-5 pl-4 border-l border-base-content/10 space-y-3 text-sm"
  defp body_class(:panel), do: "border-t border-base-content/10 px-4 py-3"
  defp body_class(:bare), do: nil
end
