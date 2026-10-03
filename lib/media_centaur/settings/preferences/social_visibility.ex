defmodule MediaCentaur.Settings.Preferences.SocialVisibility do
  @moduledoc """
  Typed accessor for the `show_social` Settings entry.

  Gates the sidebar's Social entry and the Review control on the title
  detail modal. Default-**on**; switched under Settings → Social, beside
  the identity and sharing it belongs with. The page stays reachable by
  URL either way, and the watchlist is unaffected — it lives on Incoming
  (UIDR-050).

  Renamed from `show_discovery` on 2026-10-03 (UIDR-051) without a data
  migration: the preference resets to its default. Default-off, under
  Settings → Preferences, until later that day (UIDR-051 amendment). The
  2026-09-02 rename from `show_watchlist` was a data migration
  (`RenameShowWatchlistSettingsKey`); that history stands.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "show_social", default: true
end
