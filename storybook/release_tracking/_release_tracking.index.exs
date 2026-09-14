defmodule MediaCentaurWeb.Storybook.ReleaseTracking do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "calendar", :light, "psb:mr-1"}

  def entry("release_dates"), do: [icon: {:fa, "calendar", :thin}, name: "Release dates"]
end
