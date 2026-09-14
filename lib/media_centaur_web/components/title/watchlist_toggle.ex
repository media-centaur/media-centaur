defmodule MediaCentaurWeb.Components.Title.WatchlistToggle do
  @moduledoc """
  The bookmark: the one click that puts a title on the watchlist and takes
  it off, worn by every action strip that shows a title (UIDR-039) — the
  title view beside Download, and the library's view controls. The Feed
  entry's toolbar wears the same glyph in its own labelled form.

  Outline off the list, solid with the primary tint on it, state in
  `aria-pressed`. A click sets List for a title with no record or an
  ignored one, and Off for a title on the list at any rung — removing a
  title from the watchlist is one act (spec 2026-09-14). Off deletes the
  record and the calendar derived from it; re-listing derives it again,
  and the title's quality acceptance survives on its own. `choice/1` is
  that rule, carried as `phx-value-choice`, so the host's handler sets
  exactly what the control said it would rather than deciding again.

  The host names the event (`event`) and passes whatever else its handler
  needs to find the title (`phx-value-ref`) through `rest`.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1, icon: 1]

  alias MediaCentaur.Discovery.TitleIntent

  attr :id, :string, required: true

  attr :rung, :atom,
    values: [nil, :ignored, :list, :follow, :grab],
    default: nil,
    doc: "the rung the title sits at; nil means Off — no record"

  attr :event, :string,
    required: true,
    doc: "the `phx-click` event the host handles; it receives `choice` as `list` or `off`"

  attr :rest, :global, doc: "`phx-value-ref` and anything else the host's handler needs"

  def watchlist_toggle(assigns) do
    assigns =
      assign(assigns,
        choice: choice(assigns.rung),
        listed?: listed?(assigns.rung),
        label: label(assigns.rung)
      )

    ~H"""
    <.button
      id={@id}
      variant="dismiss"
      size="sm"
      shape="circle"
      class={[
        "ml-1 transition-opacity",
        if(@listed?, do: "text-primary", else: "opacity-60 hover:opacity-100")
      ]}
      phx-click={@event}
      phx-value-choice={@choice}
      data-nav-item
      tabindex="0"
      aria-pressed={to_string(@listed?)}
      title={@label}
      aria-label={@label}
      {@rest}
    >
      <.icon name={if @listed?, do: "hero-bookmark-solid", else: "hero-bookmark"} class="size-5" />
    </.button>
    """
  end

  @doc ~s(What a click sets: `"list"` off the list or ignored; `"off"` at any listed rung.)
  @spec choice(TitleIntent.rung() | nil) :: String.t()
  def choice(nil), do: "list"
  def choice(:ignored), do: "list"
  def choice(_listed), do: "off"

  @doc "Whether the bookmark is filled: the title is at List or above."
  @spec listed?(TitleIntent.rung() | nil) :: boolean()
  def listed?(nil), do: false
  def listed?(:ignored), do: false
  def listed?(_listed), do: true

  @doc "The accessible name — what the click does."
  @spec label(TitleIntent.rung() | nil) :: String.t()
  def label(nil), do: "Add to watchlist"
  def label(:ignored), do: "Add to watchlist"
  def label(_listed), do: "On your list — remove"
end
