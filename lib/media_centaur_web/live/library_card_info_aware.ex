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

  defmacro __using__(_opts) do
    quote do
      on_mount {MediaCentaurWeb.Live.SettingAware,
                {MediaCentaur.Settings.Preferences.LibraryCardInfo, :show_card_info,
                 :setting_aware_show_card_info}}
    end
  end
end
