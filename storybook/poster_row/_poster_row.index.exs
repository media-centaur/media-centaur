defmodule MediaCentaurWeb.Storybook.PosterRow do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "grip-horizontal", :light, "psb:mr-1"}

  def entry("poster_row"), do: [icon: {:fa, "images", :thin}, name: "Poster row"]
  def entry("grouped_poster_row"), do: [icon: {:fa, "table-columns", :thin}, name: "Grouped poster row"]
end
