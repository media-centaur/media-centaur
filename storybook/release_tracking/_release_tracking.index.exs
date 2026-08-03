defmodule MediaCentaurWeb.Storybook.ReleaseTracking do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "calendar", :light, "psb:mr-1"}

  def entry("title_modal"), do: [icon: {:fa, "panorama", :thin}, name: "Title modal"]
end
