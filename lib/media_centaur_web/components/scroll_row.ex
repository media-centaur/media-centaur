defmodule MediaCentaurWeb.Components.ScrollRow do
  @moduledoc """
  A scroll row: a horizontally scrolling `.row-scroll` track of cards with
  its pointer chrome — an edge arrow at each end that glides the track one
  step that way. Home's Continue Watching and Recently Added rows and the
  title detail's collection rail render their track through it; the hero,
  one full-bleed item, has nothing to scroll and keeps its plain track.

  The track owns the scroll system (`app.css`: the ring reserve, hidden
  scrollbar, cursor peek, edge fades); the `variant` picks its card size.
  `rest` lands on the track, so a caller's `data-component` or
  `data-nav-zone` sits where it always did.

  The arrows are a pointer affordance in the play overlay's sense
  (UIDR-027) and take its shape: a reveal wrapper (`.scroll-row-arrow`) that
  hover fades in — opacity only, after `--hover-reveal-delay`, under
  `(hover: hover)` — around a `.picture-button`, the disc the play overlay
  draws. The button is outside the input system (`tabindex="-1"`, no
  `data-nav-item`) and never takes the cursor (the hook prevents default on
  mousedown); it keeps an `aria-label`, as every icon-only control does. The
  TV, which has no pointer, never sees them. The `ScrollRow` hook
  (`assets/js/hooks/scroll_row.js`) writes the track's edge state onto it as
  `data-at-start` / `data-at-end`; CSS drops the arrow pointing at an end
  already reached, so a track that fits shows none.
  """

  use Phoenix.Component
  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  attr :id, :string, required: true, doc: "the hook element's id; unique on the page"

  attr :variant, :atom,
    required: true,
    values: [:backdrop_lg, :poster, :backdrop_sm],
    doc:
      "the track's card size: `:backdrop_lg` (Continue Watching), `:poster` (Recently Added), `:backdrop_sm` (the collection rail)"

  attr :rest, :global, doc: "lands on the track — not `class`, the variant owns it"

  slot :inner_block, required: true, doc: "the cards"

  def scroll_row(assigns) do
    ~H"""
    <div id={@id} phx-hook="ScrollRow" class="scroll-row">
      <div class={["row-scroll", track_class(@variant)]} {@rest}>
        {render_slot(@inner_block)}
      </div>
      <%!-- The arrows follow the track: the edge-state CSS reaches them with `~`. --%>
      <.edge_arrow direction="left" />
      <.edge_arrow direction="right" />
    </div>
    """
  end

  attr :direction, :string, values: ["left", "right"], required: true

  defp edge_arrow(assigns) do
    ~H"""
    <div class="scroll-row-arrow" data-scroll-row-arrow={@direction}>
      <button type="button" class="picture-button" tabindex="-1" aria-label={"Scroll #{@direction}"}>
        <.icon name={"hero-chevron-#{@direction}-mini"} class="size-5" />
      </button>
    </div>
    """
  end

  defp track_class(:backdrop_lg), do: "row-scroll-backdrop-lg"
  defp track_class(:poster), do: "row-scroll-poster"
  defp track_class(:backdrop_sm), do: "row-scroll-backdrop-sm"
end
