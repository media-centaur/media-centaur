defmodule MediaCentaurWeb.Live.LetterboxdLinksAware do
  @moduledoc """
  Shared `:letterboxd_links` lifecycle for any LiveView that renders the
  detail modal's Letterboxd link (Home, Library) or its settings toggle
  (Settings).

  `use MediaCentaurWeb.Live.LetterboxdLinksAware` registers the generic
  `MediaCentaurWeb.Live.SettingAware` on_mount with the
  `MediaCentaur.LetterboxdLinks` context: it subscribes to Settings
  updates, seeds the assign, and re-assigns on
  `{:setting_changed, "letterboxd_links", _}`. Hosts MUST NOT call
  `Settings.subscribe()` themselves (Credo MC0011).
  """

  defmacro __using__(_opts) do
    quote do
      on_mount {MediaCentaurWeb.Live.SettingAware,
                {MediaCentaur.LetterboxdLinks, :letterboxd_links, :setting_aware_letterboxd_links}}
    end
  end
end
