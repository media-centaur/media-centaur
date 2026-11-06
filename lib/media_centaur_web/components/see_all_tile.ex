defmodule MediaCentaurWeb.Components.SeeAllTile do
  @moduledoc """
  The tile at the end of a shelf that has a page of its own: an arrow and
  *See all*, navigating to that page. It is the keyboard and gamepad way to
  the page — the shelf head's *See all →* link is pointer-only — so every
  shelf with a page ends in one. Continue Watching, Recently Added and the
  marquee compose it; `shape` matches the cards beside it.
  """
  use Phoenix.Component
  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  attr :navigate, :string, required: true, doc: "the shelf's page"

  attr :shape, :atom,
    required: true,
    values: [:poster, :backdrop, :fill],
    doc: "`:poster` 2:3, `:backdrop` 16:9, `:fill` takes the slot it is given (a marquee column)"

  attr :class, :string, default: nil, doc: "extra utilities — the slot's sizing"

  attr :rest, :global, doc: "lands on the link — a caller's `data-component`"

  def see_all_tile(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "card-hover relative overflow-hidden glass-inset flex flex-col items-center justify-center gap-2 text-base-content/60 hover:text-primary hover:bg-base-content/5",
        shape_class(@shape),
        @class
      ]}
      data-row-item
      data-nav-item
      tabindex="0"
      {@rest}
    >
      <.icon name="hero-arrow-right-circle" class="size-10" />
      <span class="text-sm font-medium">See all</span>
    </.link>
    """
  end

  defp shape_class(:poster), do: "aspect-[2/3] rounded"
  defp shape_class(:backdrop), do: "aspect-[16/9] rounded-lg"
  defp shape_class(:fill), do: "rounded-lg"
end
