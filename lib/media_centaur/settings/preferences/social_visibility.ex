defmodule MediaCentaur.Settings.Preferences.SocialVisibility do
  @moduledoc """
  Typed accessor for the `show_social` Settings entry.

  Gates the sidebar's Social entry and the Review control on the title
  detail modal. Default-**off**: the Social page is an early preview, so
  it stays out of the sidebar until a person opts in under Settings →
  Preferences. The page stays reachable by URL and the watchlist is
  unaffected — it lives on Incoming (UIDR-050).

  Renamed from `show_discovery` on 2026-10-03 (UIDR-051) without a data
  migration: the preference resets to its default. The 2026-09-02 rename
  from `show_watchlist` was a data migration
  (`RenameShowWatchlistSettingsKey`); that history stands.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "show_social", default: false
end
