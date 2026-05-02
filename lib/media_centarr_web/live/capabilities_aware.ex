defmodule MediaCentarrWeb.Live.CapabilitiesAware do
  @moduledoc """
  Shared `:tmdb_ready` lifecycle for any LiveView that only gates UI on
  the `Capabilities.tmdb_ready?/0` boolean (Home, Library).

  `use MediaCentarrWeb.Live.CapabilitiesAware` registers an `on_mount`
  callback that:

    * subscribes to `MediaCentarr.Capabilities` (when connected) so live
      updates flow into this LiveView
    * seeds `:tmdb_ready` from the current value
    * attaches a `:handle_info` hook that re-assigns `:tmdb_ready`
      whenever `:capabilities_changed` arrives, then returns
      `{:cont, socket}` so the host's own `handle_info/2` clauses still
      run for any bespoke capability work

  The host cannot forget any of this — it is structurally impossible to
  mount the trait without the wiring. Hosts MUST NOT call
  `Capabilities.subscribe()` themselves; the `EntityModalContract` Credo
  check (which covers all auto-wiring traits) flags the duplicate.

  ## Co-existing with bespoke `:capabilities_changed` handlers

  Earlier iterations of this trait *injected* a `handle_info/2` clause
  for `:capabilities_changed`, which collided with hosts that needed
  extra work on the same message (UpcomingLive also assigns
  `:acquisition_ready`; AcquisitionLive re-arms polling and may navigate
  away on a downgrade). Those hosts had to opt out of the macro.

  The on_mount + `attach_hook` model removes that constraint. The hook
  updates `:tmdb_ready` and returns `{:cont, socket}`, so the host's own
  `handle_info(:capabilities_changed, _)` clause still fires and can do
  whatever extra work it needs. Adopting this trait is now a free win.

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
  seeds the assign, and attaches the PubSub hook.
  """
  def on_mount(:default, _params, _session, socket) do
    socket = Phoenix.Component.assign(socket, :tmdb_ready, Capabilities.tmdb_ready?())

    if Phoenix.LiveView.connected?(socket) do
      Capabilities.subscribe()
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
    {:cont, Phoenix.Component.assign(socket, :tmdb_ready, Capabilities.tmdb_ready?())}
  end

  def handle_capabilities_changed(_msg, socket), do: {:cont, socket}
end
