defmodule MediaCentaur.Settings.Preferences.AutoPlayNextEpisode do
  @moduledoc """
  Typed accessor for the `auto_play_next_episode` Settings entry.

  Controls whether a TV episode playback session queues the following
  episode onto the mpv playlist (ADR-062) — auto-advance at end of file
  plus the in-player "Next Episode" affordance during credits. Default-
  **on**; the entry is only written when the user opts out. Read at each
  queueing decision, so flipping it mid-session affects the next episode
  boundary without a restart.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "auto_play_next_episode", default: true
end
