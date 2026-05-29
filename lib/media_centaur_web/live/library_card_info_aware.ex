defmodule MediaCentaurWeb.Live.LibraryCardInfoAware do
  @moduledoc """
  Shared `:show_card_info` lifecycle for any LiveView that renders
  `LibraryCards.poster_card` and must honour the user's
  `library_show_card_info` preference (Library, Settings, anywhere the
  poster card is exposed).

  `use MediaCentaurWeb.Live.LibraryCardInfoAware` registers an
  `on_mount` callback that:

    * subscribes to `MediaCentaur.Settings` (when connected) so live
      updates flow into this LiveView
    * seeds `:show_card_info` from the current
      `LibraryCardInfo.enabled?/0` value
    * attaches a `:handle_info` hook that re-assigns `:show_card_info`
      whenever `{:setting_changed, "library_show_card_info", _}`
      arrives, then returns `{:cont, socket}` so the host's own
      `handle_info/2` clauses still run for any other setting keys it
      cares about

  The host cannot forget any of this — it is structurally impossible to
  mount the trait without the wiring. Hosts MUST NOT call
  `Settings.subscribe()` themselves; a duplicate subscribe is wasted
  PubSub fanout and the trait already covers the topic for the whole
  family of setting-aware LiveViews.

  Decoupling rationale: mirror of `SpoilerFreeAware` (ADR-038).
  """

  alias MediaCentaur.LibraryCardInfo
  alias MediaCentaur.Settings

  defmacro __using__(_opts) do
    quote do
      on_mount {MediaCentaurWeb.Live.LibraryCardInfoAware, :default}
    end
  end

  @doc """
  Auto-wires every host that `use`s this module. Subscribes once,
  seeds the assign, and attaches the PubSub hook.
  """
  def on_mount(:default, _params, _session, socket) do
    socket = Phoenix.Component.assign(socket, :show_card_info, LibraryCardInfo.enabled?())

    if Phoenix.LiveView.connected?(socket) do
      Settings.subscribe()
    end

    socket =
      Phoenix.LiveView.attach_hook(
        socket,
        :library_card_info_aware,
        :handle_info,
        &__MODULE__.handle_setting_changed/2
      )

    {:cont, socket}
  end

  @doc false
  def handle_setting_changed({:setting_changed, key, value}, socket) do
    if key == LibraryCardInfo.setting_key() do
      {:cont, Phoenix.Component.assign(socket, :show_card_info, enabled?(value))}
    else
      {:cont, socket}
    end
  end

  def handle_setting_changed(_msg, socket), do: {:cont, socket}

  defp enabled?(%{"enabled" => false}), do: false
  defp enabled?(_), do: true
end
