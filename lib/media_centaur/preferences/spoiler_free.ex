defmodule MediaCentaur.Preferences.SpoilerFree do
  @moduledoc """
  Typed accessor for the `spoiler_free_mode` Settings entry.

  Default-off: only an explicit opt-in enables spoiler-free mode.
  """

  use MediaCentaur.Preferences.BooleanSetting, key: "spoiler_free_mode", default: false
end
