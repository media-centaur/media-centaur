defmodule MediaCentaurWeb.Live.IntentAware do
  @moduledoc """
  Shared `:title_rungs` lifecycle for any LiveView that renders a title's
  place on the ladder (Incoming search rows, the detail modal hosts).

  `use MediaCentaurWeb.Live.IntentAware` registers this module's
  `on_mount` callback: it subscribes to `discovery:updates`, seeds
  `%{{tmdb_id, media_type} => rung}` from `Discovery.rungs/0`, and
  attaches a `:handle_info` hook that refreshes it on
  `{:title_intent_changed, _}` — halting that message so hosts need no
  clause for it. Hosts MUST NOT call `Discovery.subscribe/0` themselves.

  It carries the rung rather than a yes/no ref set because a row now
  shows *where* a title sits, not merely that it is listed.

  `DiscoveryLive` does NOT use this module — it needs the full record
  list and subscribes directly.
  """

  alias MediaCentaur.Discovery

  defmacro __using__(_opts) do
    quote do
      on_mount {MediaCentaurWeb.Live.IntentAware, :default}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    if Phoenix.LiveView.connected?(socket), do: Discovery.subscribe()

    socket =
      socket
      |> Phoenix.Component.assign(:title_rungs, Discovery.rungs())
      |> Phoenix.LiveView.attach_hook(:title_rung_refresh, :handle_info, &refresh/2)

    {:cont, socket}
  end

  defp refresh({:title_intent_changed, _event}, socket) do
    {:halt, Phoenix.Component.assign(socket, :title_rungs, Discovery.rungs())}
  end

  defp refresh(_message, socket), do: {:cont, socket}
end
