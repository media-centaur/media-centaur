defmodule MediaCentaur.SpoilerFree do
  use Boundary, deps: [MediaCentaur.Settings, {MediaCentaur.BooleanSetting, :compile}]

  @moduledoc """
  Typed accessor for the `spoiler_free_mode` Settings entry.

  Default-off: only an explicit opt-in enables spoiler-free mode.
  """

  use MediaCentaur.BooleanSetting, key: "spoiler_free_mode", default: false
end
