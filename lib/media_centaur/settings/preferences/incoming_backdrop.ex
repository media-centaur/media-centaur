defmodule MediaCentaur.Settings.Preferences.IncomingBackdrop do
  @moduledoc """
  Typed accessor for the `incoming_backdrop` Settings entry — whether the
  Incoming page renders its ambient artwork band (`.page-atmosphere`).
  The dark scrim underneath is unconditional; this flag only controls the
  image.

  Default-off: a fresh install renders no backdrop until the user turns
  it on. Installs that predate the flip keep their backdrop via the
  `SeedBackdropDefaultsForExistingInstalls` migration, which seeds an
  explicit `enabled: true` row on non-empty databases.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "incoming_backdrop", default: false
end
