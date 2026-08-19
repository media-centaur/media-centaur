defmodule MediaCentaurWeb.Live.IncomingBackdropAware do
  @moduledoc """
  Shared `:incoming_backdrop` lifecycle for any LiveView that renders (or
  toggles) the Incoming page's ambient artwork band (Incoming, Settings).

  `use MediaCentaurWeb.Live.IncomingBackdropAware` registers an `on_mount`
  callback that subscribes to `MediaCentaur.Settings`, seeds
  `:incoming_backdrop` from `IncomingBackdrop.enabled?/0`, and re-assigns
  on every `{:setting_changed, "incoming_backdrop", _}` — see
  `MediaCentaurWeb.Live.SettingAware` for the shared mechanics and the
  no-manual-subscribe rule (Credo MC0011).
  """

  defmacro __using__(_opts) do
    quote do
      on_mount {MediaCentaurWeb.Live.SettingAware,
                {MediaCentaur.Settings.Preferences.IncomingBackdrop, :incoming_backdrop,
                 :setting_aware_incoming_backdrop}}
    end
  end
end
