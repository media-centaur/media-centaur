defmodule MediaCentaurWeb.Components.Title.WatchlistToggle do
  @moduledoc """
  The bookmark: the one click that puts a title on the watchlist and takes
  it off, worn by every action strip that shows a title (UIDR-039) — the
  title view beside Download, and the library's view controls. The Feed
  entry's toolbar wears the same glyph in its own labelled form.

  Outline off the list, solid with the primary tint on it, state in
  `aria-pressed`. It works the bottom of the record only: a click sets
  List for a title with no record or an ignored one, Off for a title at
  List, and at Follow and above it is a marker with no click at all — a
  one-click must not tear down a release calendar, so Off is in the
  tracking controls. `choice/1` is that rule, carried as
  `phx-value-choice`, so the host's handler sets exactly what the control
  said it would rather than deciding again.

  The host names the event (`event`) and passes whatever else its handler
  needs to find the title (`phx-value-ref`) through `rest`.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1, icon: 1]

  alias MediaCentaur.Discovery.TitleIntent

  attr :id, :string, required: true

  attr :rung, :atom,
    values: [nil, :ignored, :list, :follow, :ask, :grab, :default],
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
      phx-click={@choice && @event}
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

  @doc """
  What a click sets: `"list"` for a title with no record or an ignored
  one, `"off"` for one at List, and nil at Follow and above — the marker.
  """
  @spec choice(TitleIntent.rung() | nil) :: String.t() | nil
  def choice(nil), do: "list"
  def choice(:ignored), do: "list"
  def choice(:list), do: "off"
  def choice(_followed), do: nil

  @doc "Whether the bookmark is filled: the title is at List or above."
  @spec listed?(TitleIntent.rung() | nil) :: boolean()
  def listed?(nil), do: false
  def listed?(:ignored), do: false
  def listed?(_listed), do: true

  @doc "The accessible name — what the click does, or that it is a marker."
  @spec label(TitleIntent.rung() | nil) :: String.t()
  def label(nil), do: "Add to watchlist"
  def label(:ignored), do: "Add to watchlist"
  def label(:list), do: "On your list — remove"
  def label(_followed), do: "On your list — tracking is set below"
end
