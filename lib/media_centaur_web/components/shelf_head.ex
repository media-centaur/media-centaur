defmodule MediaCentaurWeb.Components.ShelfHead do
  @moduledoc """
  The head over a shelf on an assembled page: the shelf's title and, when
  the shelf has a page of its own, a quiet *See all* link at the right.
  Home's three shelves and Discovery's compose it; a shelf's `<section>`
  carries the nav zone and the reveal attributes, this draws only the
  line above the row.
  """
  use Phoenix.Component

  attr :title, :string, required: true, doc: "the shelf's name, as its heading"

  attr :see_all_href, :string,
    default: nil,
    doc: "where the whole shelf lives; nil for a shelf that is complete here"

  def shelf_head(assigns) do
    ~H"""
    <div class="flex items-baseline justify-between mb-3" data-component="shelf-head">
      <h2 class="text-xl font-semibold tracking-tight">{@title}</h2>
      <%!-- On a coarse pointer the link's box grows to the touch floor
            (48 px) without moving the line: padding in, the same margin out. --%>
      <.link
        :if={@see_all_href}
        navigate={@see_all_href}
        class="text-sm text-base-content/60 hover:text-primary pointer-coarse:inline-flex pointer-coarse:items-center pointer-coarse:min-h-12 pointer-coarse:px-3 pointer-coarse:-mx-3 pointer-coarse:-my-3.5"
      >
        See all →
      </.link>
    </div>
    """
  end
end
