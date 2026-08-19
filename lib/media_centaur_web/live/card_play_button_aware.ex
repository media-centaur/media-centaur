defmodule MediaCentaurWeb.Live.CardPlayButtonAware do
  @moduledoc """
  Shared `:show_play_button` lifecycle for any LiveView that renders
  cards carrying the hover play overlay (UIDR-027) and must honour the
  user's `card_play_button` preference (Home, Library, Settings).

  `use MediaCentaurWeb.Live.CardPlayButtonAware` registers the generic
  `SettingAware` on_mount callback with `MediaCentaur.Preferences.CardPlayButton`:
  subscribes to Settings updates, seeds `:show_play_button`, and
  re-assigns it on `{:setting_changed, "card_play_button", _}`. Hosts
  MUST NOT call `Settings.subscribe/0` themselves (Credo MC0011).

  Decoupling rationale: mirror of `LibraryCardInfoAware`.
  """

  defmacro __using__(_opts) do
    quote do
      on_mount {MediaCentaurWeb.Live.SettingAware,
                {MediaCentaur.Preferences.CardPlayButton, :show_play_button,
                 :setting_aware_show_play_button}}
    end
  end
end
