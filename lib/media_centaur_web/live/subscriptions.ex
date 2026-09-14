defmodule MediaCentaurWeb.Live.Subscriptions do
  @moduledoc """
  The one door a LiveView process subscribes to a context's topic through.

  Every consumer — a page, a trait, the title detail host — declares the
  topics it needs by calling `subscribe/2` with the context that owns the
  topic; the first call for a context subscribes, a later call by another
  consumer in the same process is a no-op. So no message is delivered
  twice, and no consumer depends on another having subscribed first.
  Nothing subscribes on the dead render: the socket must be connected.

  `context` is a module with a `subscribe/0` (`MediaCentaur.Library`,
  `MediaCentaur.Playback`, …) or a `{module, function}` pair naming one
  of a context's other subscribe doors (`{MediaCentaur.Acquisition,
  :subscribe_queue}`). The set of what this process holds lives in the
  `:subscriptions` assign.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1]

  @type subscription :: module() | {module(), atom()}

  @spec subscribe(Phoenix.LiveView.Socket.t(), subscription()) :: Phoenix.LiveView.Socket.t()
  def subscribe(socket, subscription) do
    held = Map.get(socket.assigns, :subscriptions, MapSet.new())

    cond do
      not connected?(socket) -> socket
      MapSet.member?(held, subscription) -> socket
      true -> subscribe_now(socket, subscription, held)
    end
  end

  defp subscribe_now(socket, subscription, held) do
    case subscription do
      {module, function} -> apply(module, function, [])
      module -> module.subscribe()
    end

    assign(socket, :subscriptions, MapSet.put(held, subscription))
  end
end
