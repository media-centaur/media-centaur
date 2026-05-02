defmodule MediaCentarrWeb.Storybook.UpcomingCards do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "calendar-days", :light, "psb:mr-1"}

  def entry("upcoming_zone"), do: [icon: {:fa, "calendar", :thin}, name: "Upcoming zone"]
end
