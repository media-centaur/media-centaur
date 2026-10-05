defmodule MediaCentaur.Settings.Preferences.MovieFinishPrompt do
  @moduledoc """
  Typed accessor for the `movie_finish_prompt` Settings entry.

  Controls whether closing mpv on a movie the session completed opens
  that movie's title with the finish prompt — Review, Delete, Done
  (UIDR-052). Default-**on**; the entry is only written when the user
  opts out. Off, the page is left as it was, as play in place promises.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "movie_finish_prompt", default: true
end
