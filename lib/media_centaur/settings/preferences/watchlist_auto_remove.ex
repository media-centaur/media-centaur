defmodule MediaCentaur.Settings.Preferences.WatchlistAutoRemove do
  @moduledoc """
  Typed accessor for the `watchlist_auto_remove` Settings entry: whether a
  movie on the watchlist leaves it when the movie arrives in the library.

  Default-**on**. The arrival is the event (`Library.Events.MoviesAdded`,
  handled by `ReleaseTracking.movies_added/1`), not the state: a movie
  already in the library that a person lists afterwards stays listed, and
  turning this on removes nothing that arrived before. Removal is the
  bookmark's Off, so a shared listing is withdrawn as it would be by hand.
  Series are untouched — they keep releasing. Set under Settings → Library.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting,
    key: "watchlist_auto_remove",
    default: true
end
