defmodule MediaCentaur.Settings.Preferences.ShareWatchlist do
  @moduledoc """
  Typed accessor for the `share_watchlist` Settings entry: whether a
  title reaching List or above on the ladder publishes a listing —
  "wants to watch" — to the user's friends (`MediaCentaur.Activities.Publisher`,
  ADR-067).

  Default-**off**. Turning it on shares from then on, never history: a
  title listed before the switch says nothing until it is listed again.
  Turning it off stops new listings; a listing already published is
  still withdrawn when its title drops below List, because the statement
  is no longer true. Set under Settings → Social → Sharing.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "share_watchlist", default: false
end
