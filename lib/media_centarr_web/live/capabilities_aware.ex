defmodule MediaCentarrWeb.Live.CapabilitiesAware do
  @moduledoc """
  Shared readiness-flag lifecycle for every LiveView in the app layout.

  `use MediaCentarrWeb.Live.CapabilitiesAware` (or registering this module
  as an `on_mount` callback on a `live_session`) wires the hosting
  LiveView to:

    * subscribe to `Topics.capabilities_updates/0` (the derived topic
      per ADR-041, never to source topics) when connected
    * seed `:tmdb_ready`, `:prowlarr_ready`, `:download_client_ready`,
      and `:acquisition_ready` from the current `Capabilities` cache
    * re-assign all four whenever `:capabilities_changed` arrives, then
      return `{:cont, socket}` so the host's own `handle_info/2` clauses
      still run for any bespoke capability work

  ## Why subscribe to the derived topic directly (not via `Capabilities.subscribe/0`)

  `Capabilities.subscribe/0` is the *worker* subscription — it subscribes
  to both `capabilities_updates` AND the source `config_updates` topic so
  the `Cache.Worker` can recompute when either input changes. LiveView
  consumers shouldn't see source events. Per ADR-041 the encapsulation
  rule is "consumers depend on view shape, not on the source events that
  produced it", so this trait subscribes directly to the derived topic
  via `Phoenix.PubSub.subscribe/2`.

  ## Co-existing with bespoke `:capabilities_changed` handlers

  The hook attaches via `attach_hook` and returns `{:cont, socket}`, so
  any `handle_info(:capabilities_changed, _)` clause the host defines
  still fires after the hook has updated the assigns. Hosts can read
  the freshly-assigned flags inside their own clause; they don't need
  to call `Capabilities.*_ready?/0` directly.

  Decoupling rationale: see ADR-038.
  """

  alias MediaCentarr.Capabilities

  defmacro __using__(_opts) do
    quote do
      on_mount {MediaCentarrWeb.Live.CapabilitiesAware, :default}
    end
  end

  @doc """
  Auto-wires every host that `use`s this module. Subscribes once,
  seeds the four readiness assigns, and attaches the PubSub hook.
  """
  def on_mount(:default, _params, _session, socket) do
    socket = assign_all_readiness(socket)

    if Phoenix.LiveView.connected?(socket) do
      Capabilities.subscribe_changes()
    end

    socket =
      Phoenix.LiveView.attach_hook(
        socket,
        :capabilities_aware,
        :handle_info,
        &__MODULE__.handle_capabilities_changed/2
      )

    {:cont, socket}
  end

  @doc false
  def handle_capabilities_changed(:capabilities_changed, socket) do
    {:cont, assign_all_readiness(socket)}
  end

  def handle_capabilities_changed(_msg, socket), do: {:cont, socket}

  defp assign_all_readiness(socket) do
    socket
    |> Phoenix.Component.assign(:tmdb_ready, Capabilities.tmdb_ready?())
    |> Phoenix.Component.assign(:prowlarr_ready, Capabilities.prowlarr_ready?())
    |> Phoenix.Component.assign(:download_client_ready, Capabilities.download_client_ready?())
    |> Phoenix.Component.assign(:acquisition_ready, Capabilities.acquisition_ready?())
  end
end
