defmodule MediaCentaurWeb.Live.WatchlistAware do
  @moduledoc """
  Shared `:watchlisted_refs` lifecycle for any LiveView that renders a
  watchlist affordance (Incoming search rows, the detail modal hosts).

  `use MediaCentaurWeb.Live.WatchlistAware` registers this module's
  `on_mount` callback: it subscribes to `discovery:updates`, seeds the
  `{tmdb_id, media_type}` ref set from `Discovery.watchlisted_refs/0`,
  and attaches a `:handle_info` hook that refreshes it on
  `{:watchlist_item_added, _}` / `{:watchlist_item_removed, _}` —
  halting those messages so hosts need no clauses for them. Hosts MUST
  NOT call `Discovery.subscribe/0` themselves.

  `WatchlistLive` does NOT use this module — it needs the full item
  list and subscribes directly.
  """

  alias MediaCentaur.Discovery

  defmacro __using__(_opts) do
    quote do
      on_mount {MediaCentaurWeb.Live.WatchlistAware, :default}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    if Phoenix.LiveView.connected?(socket), do: Discovery.subscribe()

    socket =
      socket
      |> Phoenix.Component.assign(:watchlisted_refs, Discovery.watchlisted_refs())
      |> Phoenix.LiveView.attach_hook(:watchlist_refresh, :handle_info, &refresh/2)

    {:cont, socket}
  end

  defp refresh({tag, _event}, socket) when tag in [:watchlist_item_added, :watchlist_item_removed] do
    {:halt, Phoenix.Component.assign(socket, :watchlisted_refs, Discovery.watchlisted_refs())}
  end

  defp refresh(_message, socket), do: {:cont, socket}
end
