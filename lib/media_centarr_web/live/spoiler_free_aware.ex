defmodule MediaCentarrWeb.Live.SpoilerFreeAware do
  @moduledoc """
  Shared `:spoiler_free` lifecycle for any LiveView that hides spoilery
  detail when the setting is on (Home, Library, Settings).

  `use MediaCentarrWeb.Live.SpoilerFreeAware` registers an `on_mount`
  callback that:

    * subscribes to `MediaCentarr.Settings` (when connected) so live
      updates flow into this LiveView
    * seeds `:spoiler_free` from the current value
    * attaches a `:handle_info` hook that re-assigns `:spoiler_free`
      whenever `{:setting_changed, "spoiler_free_mode", _}` arrives, then
      returns `{:cont, socket}` so the host's own `handle_info/2` clauses
      still run for any other setting keys it cares about

  The host cannot forget any of this — it is structurally impossible to
  mount the trait without the wiring. Hosts MUST NOT call
  `Settings.subscribe()` themselves; the `EntityModalContract` Credo
  check (which covers all auto-wiring traits) flags the duplicate.

  Decoupling rationale: see ADR-038. Before the on_mount migration each
  host had to remember to subscribe, seed the assign, AND not collide
  with another `handle_info(:setting_changed, ...)` clause — a contract
  the EntityModal class-of-bug exposed as fragile.
  """

  alias MediaCentarr.Settings

  @setting_key "spoiler_free_mode"

  defmacro __using__(_opts) do
    quote do
      on_mount {MediaCentarrWeb.Live.SpoilerFreeAware, :default}
    end
  end

  @doc """
  Auto-wires every host that `use`s this module. Subscribes once,
  seeds the assign, and attaches the PubSub hook.
  """
  def on_mount(:default, _params, _session, socket) do
    socket = Phoenix.Component.assign(socket, :spoiler_free, current_value())

    if Phoenix.LiveView.connected?(socket) do
      Settings.subscribe()
    end

    socket =
      Phoenix.LiveView.attach_hook(
        socket,
        :spoiler_free_aware,
        :handle_info,
        &__MODULE__.handle_setting_changed/2
      )

    {:cont, socket}
  end

  @doc false
  def handle_setting_changed({:setting_changed, @setting_key, enabled}, socket) do
    {:cont, Phoenix.Component.assign(socket, :spoiler_free, enabled == true)}
  end

  def handle_setting_changed(_msg, socket), do: {:cont, socket}

  defp current_value do
    case Settings.get_by_key(@setting_key) do
      {:ok, %{value: %{"enabled" => enabled}}} -> enabled == true
      _ -> false
    end
  end
end
