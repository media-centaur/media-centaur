defmodule MediaCentaur.Settings.Preferences.FinishPrompt do
  @moduledoc """
  Typed accessor for the `finish_prompt` Settings entry.

  Controls whether closing mpv after finishing a title opens it with the
  finish prompt (UIDR-052): a movie, standalone or in a collection, or a
  show's latest aired episode. Default-**on**; the entry is only written
  when the user opts out. Off, the page is left as it was, as play in
  place promises.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "finish_prompt", default: true
end
