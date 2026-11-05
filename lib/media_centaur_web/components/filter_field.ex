defmodule MediaCentaurWeb.Components.FilterField do
  @moduledoc """
  The house filter field: a search icon in a pill whose input narrows a
  list as you type — Library's toolbar, the cast panel, Review's bulk
  list. At rest and empty it shows as the icon pill; focus or text widens
  it (`.library-filter*` in `app.css`).

  The caller owns the form and its `phx-change`; the field is its input.
  With `clear_event`, a clear button shows while there is text.
  """
  use MediaCentaurWeb, :html

  attr :id, :string, default: nil
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, required: true
  attr :aria_label, :string, required: true
  attr :type, :string, default: "text", values: ~w(text search)
  attr :debounce, :string, default: "150"
  attr :clear_event, :string, default: nil, doc: "pushed by the clear button, shown while there is text."
  attr :class, :any, default: "w-56", doc: "the input's width and any tint."

  @doc "A filter input in the house pill, with an optional clear button."
  def filter_field(assigns) do
    ~H"""
    <div class="library-filter-wrap">
      <.icon name="hero-magnifying-glass-mini" class="library-filter-icon" />
      <input
        id={@id}
        type={@type}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        aria-label={@aria_label}
        phx-debounce={@debounce}
        class={["input library-filter", @class]}
        data-nav-item
        tabindex="0"
      />
      <button
        :if={@clear_event && @value not in [nil, ""]}
        type="button"
        phx-click={@clear_event}
        class="library-filter-clear"
        aria-label="Clear search"
        tabindex="0"
      >
        <.icon name="hero-x-mark-mini" class="size-4" />
      </button>
    </div>
    """
  end
end
