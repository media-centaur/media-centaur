defmodule MediaCentaurWeb.Components.ReviewListItem do
  @moduledoc """
  One row of a review queue's master list — the Identity queue's file
  groups (`ReviewLive`) and Episode mapping's shows (`EpisodeMappingLive`).
  A nav item; the selected row carries the selected tint and
  `aria-current`. The host passes its select event and `phx-value-*`
  through `rest` and draws the row's content in the slot.
  """

  use Phoenix.Component

  attr :id, :string, required: true
  attr :selected, :boolean, default: false, doc: "the row the detail pane shows."

  attr :rest, :global,
    doc: "the host's select event (`phx-click`, `phx-focus`), its `phx-value-*`, data hooks."

  slot :inner_block, required: true, doc: "the row's content: a thumbnail, its lines, a reason."

  def review_list_item(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      class={[
        "w-full text-left flex items-center gap-3 py-2 px-3 rounded-md cursor-pointer relative",
        "border border-transparent transition-[background,opacity] duration-150 hover:bg-base-content/6",
        @selected && "bg-primary/12 !border-primary/25"
      ]}
      aria-current={@selected && "true"}
      data-nav-item
      tabindex="0"
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end
end
