defmodule MediaCentaur.Settings.Preferences.ShareWatched do
  @moduledoc """
  Typed accessor for the `share_watched` Settings entry: whether finishing
  a movie or an episode publishes a watched activity to the user's
  friends (`MediaCentaur.Activities.Publisher`).

  Default-**off**: what a person watches is theirs until they choose to
  share it. Turning it on shares completions from then on, never
  history; turning it off stops new ones and leaves what was already
  published on the relays until withdrawn from the Feed. Set under
  Settings → Social → Sharing.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "share_watched", default: false
end
