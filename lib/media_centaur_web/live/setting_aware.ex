defmodule MediaCentaurWeb.Live.SettingAware do
  @moduledoc """
  Generic `on_mount` callback for a LiveView assign backed by a boolean
  `Settings` entry. The named traits (`SpoilerFreeAware`,
  `LibraryCardInfoAware`) register it with their context module and assign:

      on_mount {MediaCentaurWeb.Live.SettingAware,
                {MediaCentaur.Settings.Preferences.SpoilerFree, :spoiler_free, :setting_aware_spoiler_free}}

  where the third element is a unique `:handle_info` hook name (a literal
  atom, so no atom is created at runtime).

  The context module owns the key and the default polarity via `setting_key/0`,
  `enabled?/0` (seed), and `enabled?/1` (parse a live update value) — so a new
  setting-aware assign is one thin trait plus those three functions, with the
  polarity stated explicitly in the context rather than copy-pasted into a
  hook.

  Responsibilities, identical for every assign:

    * subscribe to `MediaCentaur.Settings` through the one door
      (`Live.Subscriptions`), so the host and every SettingAware trait it
      mounts share one subscription
    * seed the assign from `context.enabled?/0`
    * attach a `:handle_info` hook that re-assigns from `context.enabled?(value)`
      whenever `{:setting_changed, context.setting_key(), value}` arrives, then
      `{:cont, socket}` so the host's own clauses and other traits still run

  Nothing calls `Settings.subscribe/0` itself (Credo MC0011).
  """

  alias MediaCentaur.Settings
  alias MediaCentaurWeb.Live.Subscriptions

  def on_mount({context, assign, hook}, _params, _session, socket) do
    socket =
      socket
      |> Phoenix.Component.assign(assign, context.enabled?())
      |> subscribe_once()
      |> Phoenix.LiveView.attach_hook(
        hook,
        :handle_info,
        &handle_setting_changed(context, assign, &1, &2)
      )

    {:cont, socket}
  end

  # One subscribe regardless of how many setting-aware assigns the host
  # mounts: the door subscribes a topic once per process.
  defp subscribe_once(socket), do: Subscriptions.subscribe(socket, Settings)

  defp handle_setting_changed(context, assign, {:setting_changed, key, value}, socket) do
    if key == context.setting_key() do
      {:cont, Phoenix.Component.assign(socket, assign, context.enabled?(value))}
    else
      {:cont, socket}
    end
  end

  defp handle_setting_changed(_context, _assign, _msg, socket), do: {:cont, socket}
end
