defmodule MediaCentaur.Settings.Preferences.AppsVisibility do
  @moduledoc """
  Typed accessor for the `show_apps` Settings entry.

  Controls whether the Apps launcher surfaces in the sidebar.
  Default-**off**: most installs are pure media centers; the launcher is
  opted into via Settings → Preferences. Only the nav entry is gated —
  `/apps` stays reachable by URL.
  """

  use MediaCentaur.Settings.Preferences.BooleanSetting, key: "show_apps", default: false
end
