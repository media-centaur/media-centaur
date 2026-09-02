defmodule MediaCentaur.Settings.Preferences.DiscoveryVisibility do
  @moduledoc """
  Typed accessor for the `show_discovery` Settings entry.

  Gates the sidebar's Discovery entry — nothing else. Default-**off**:
  Discovery is a work-in-progress feature expected to change shape, so it
  stays out of everyone's sidebar until a user opts in via Settings →
  Preferences. The page itself stays reachable by URL, the bookmark
  toggles on the detail modal and the Incoming search rows keep working,
  and the Discovery context underneath is unaffected — items already on
  the watchlist are kept, just not linked to from the nav.

  Renamed from `show_watchlist` on 2026-09-02 (data migration
  `RenameShowWatchlistSettingsKey`) when the Watchlist page became the
  Discovery page.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "show_discovery", default: false
end
