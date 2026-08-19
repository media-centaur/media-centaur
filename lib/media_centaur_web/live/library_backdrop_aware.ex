defmodule MediaCentaurWeb.Live.LibraryBackdropAware do
  @moduledoc """
  Shared `:library_backdrop` lifecycle for any LiveView that renders (or
  toggles) the Library page's ambient artwork band (Library, Settings).

  `use MediaCentaurWeb.Live.LibraryBackdropAware` registers an `on_mount`
  callback that subscribes to `MediaCentaur.Settings`, seeds
  `:library_backdrop` from `LibraryBackdrop.enabled?/0`, and re-assigns on
  every `{:setting_changed, "library_backdrop", _}` — see
  `MediaCentaurWeb.Live.SettingAware` for the shared mechanics and the
  no-manual-subscribe rule (Credo MC0011).
  """

  defmacro __using__(_opts) do
    quote do
      on_mount {MediaCentaurWeb.Live.SettingAware,
                {MediaCentaur.Preferences.LibraryBackdrop, :library_backdrop,
                 :setting_aware_library_backdrop}}
    end
  end
end
