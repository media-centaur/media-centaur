defmodule MediaCentaurWeb.Storybook.ReleaseTracking do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "calendar", :light, "psb:mr-1"}

  def entry("mini_month"), do: [icon: {:fa, "calendar-days", :thin}, name: "Mini month"]
  def entry("title_detail"), do: [icon: {:fa, "panorama", :thin}, name: "Title detail"]
end
