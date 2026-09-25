defmodule MediaCentaurWeb.Components.TabStrip do
  @moduledoc """
  Tab strip joining sibling pages that share one sidebar entry — Review's
  identity and episode-mapping pages, Discovery's watchlist (and, later,
  feed and friends). Each tab is a navigation link to a page, not in-page
  state, and may carry a pending count.

  One `zone-tabs` nav zone; the host page declares where the strip sits
  in its layout in `assets/js/input/config.js` (see the `review` entry).
  """

  use MediaCentaurWeb, :html

  defmodule Tab do
    @moduledoc """
    One tab. `id` is what `active` matches; `navigate` is the page it
    opens; `count` is the badge (hidden at 0).
    """
    @enforce_keys [:id, :label, :navigate]
    defstruct [:id, :label, :navigate, count: 0]

    @type t :: %__MODULE__{
            id: atom(),
            label: String.t(),
            navigate: String.t(),
            count: non_neg_integer()
          }
  end

  attr :tabs, :list, required: true, doc: "`Tab.t()` in display order"
  attr :active, :atom, required: true, doc: "the `Tab` id of the page rendering the strip"

  attr :size, :atom,
    default: :md,
    values: [:md, :lg],
    doc:
      "`:lg` is the couch size — 22px tabs with 18px counts — for a surface read from the sofa (UIDR-046)"

  def tab_strip(assigns) do
    ~H"""
    <div
      data-nav-zone="zone-tabs"
      class={["flex items-baseline", if(@size == :lg, do: "tab-strip-lg gap-7", else: "gap-5")]}
      data-size={@size}
    >
      <.link
        :for={tab <- @tabs}
        navigate={tab.navigate}
        class={["zone-tab", @active == tab.id && "zone-tab-active"]}
        data-nav-item
        tabindex="0"
      >
        {tab.label}
        <.badge
          :if={tab.count > 0}
          variant="ghost"
          size={if(@size == :lg, do: "sm", else: "xs")}
          class="ml-1"
        >
          {tab.count}
        </.badge>
      </.link>
    </div>
    """
  end
end
