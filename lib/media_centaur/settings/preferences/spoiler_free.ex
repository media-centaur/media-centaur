defmodule MediaCentaur.Settings.Preferences.SpoilerFree do
  @moduledoc """
  Typed accessor for the `spoiler_free_mode` Settings entry.

  Default-off: only an explicit opt-in enables spoiler-free mode.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "spoiler_free_mode", default: false
end
