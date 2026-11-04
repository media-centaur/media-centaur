defmodule MediaCentaurWeb.Storybook.ReleaseTracking do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "calendar", :light, "psb:mr-1"}

  def entry("release_dates"), do: [icon: {:fa, "calendar", :thin}, name: "Release dates"]
  def entry("caught_up_row"), do: [icon: {:fa, "flag-checkered", :thin}, name: "Caught up"]
end
