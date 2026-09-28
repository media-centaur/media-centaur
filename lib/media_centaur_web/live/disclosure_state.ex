defmodule MediaCentaurWeb.Live.DisclosureState do
  @moduledoc """
  Which disclosures a page's user has opened or closed: the state behind
  `Components.Disclosure.disclosure/1` when no other handler needs it.

  A page holds, in `:disclosures`, the ids of the disclosures the user has
  toggled. A disclosure is open when its default is flipped by that set, so
  a host passes `open={DisclosureState.open?(@disclosures, id)}` and writes
  no handler and seeds nothing. The state lives in the LiveView, like every
  other decision about what is rendered: a patch never closes a disclosure
  the user opened, the body is not rendered while closed, and the input
  system reads `aria-expanded` from the server's render.

  Registered as an `on_mount` on the `:default` live session. Its
  `handle_event` hook answers `"disclosure:toggle"` with the disclosure's
  `id` and halts. A disclosure whose state another handler reads (a season
  list, a pursuit group, the journal) keeps its state in its host and sends
  its own event instead.

  A LiveComponent's events do not reach the hook; one that holds a
  disclosure keeps its own `:disclosures` and calls `toggle/2`.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView

  @typedoc "The ids of the disclosures toggled away from their default."
  @type t :: MapSet.t(String.t())

  @event "disclosure:toggle"

  @doc "The event a hook-owned disclosure's head sends."
  @spec event() :: String.t()
  def event, do: @event

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> assign(:disclosures, MapSet.new())
     |> LiveView.attach_hook(:disclosure_toggle, :handle_event, &toggle_on_event/3)}
  end

  @doc "True when the disclosure `id` is open: its default, flipped if toggled."
  @spec open?(t(), String.t(), boolean()) :: boolean()
  def open?(toggled, id, default \\ false), do: MapSet.member?(toggled, id) != default

  @doc "Records one toggle of `id`: a second toggle cancels the first."
  @spec toggle(t(), String.t()) :: t()
  def toggle(toggled, id) do
    if MapSet.member?(toggled, id),
      do: MapSet.delete(toggled, id),
      else: MapSet.put(toggled, id)
  end

  defp toggle_on_event(@event, %{"id" => id}, socket) when is_binary(id),
    do: {:halt, assign(socket, :disclosures, toggle(socket.assigns.disclosures, id))}

  defp toggle_on_event(_event, _params, socket), do: {:cont, socket}
end
