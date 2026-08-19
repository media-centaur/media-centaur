defmodule MediaCentaur.Settings.Preferences.WatchlistVisibility do
  @moduledoc """
  Typed accessor for the `show_watchlist` Settings entry.

  Controls whether the watchlist surfaces at all: the sidebar entry, the
  `/watchlist` page (which redirects home when hidden), the detail modal's
  bookmark toggle, and the Incoming search rows' bookmark. Default-**off**:
  the watchlist is a work-in-progress feature expected to change shape, so
  it stays out of everyone's UI until a user opts in via Settings →
  Preferences. The Discovery context underneath is unaffected — items
  already on the watchlist are kept, just not shown.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "show_watchlist", default: false
end
