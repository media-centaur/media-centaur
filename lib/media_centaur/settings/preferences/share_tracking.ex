defmodule MediaCentaur.Settings.Preferences.ShareTracking do
  @moduledoc """
  Typed accessor for the `share_tracking` Settings entry: whether starting
  to track a release publishes a tracking activity to the user's friends
  (`MediaCentaur.Activities.Publisher`).

  Default-**off**. Only a person's own act counts — a tracking item the
  library scan creates is never shared. Turning it on shares from then
  on, never history; turning it off stops new ones and leaves what was
  already published on the relays until withdrawn from the Feed. Set
  under Settings → Social → Sharing.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "share_tracking", default: false
end
