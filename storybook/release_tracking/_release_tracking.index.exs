defmodule MediaCentaurWeb.Storybook.ReleaseTracking do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "calendar", :light, "psb:mr-1"}

  def entry("release_timeline"), do: [icon: {:fa, "timeline", :thin}, name: "Release timeline"]

  def entry("tracking_mode_control"), do: [icon: {:fa, "sliders", :thin}, name: "Tracking mode control"]
end
