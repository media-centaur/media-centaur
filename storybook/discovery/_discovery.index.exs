defmodule MediaCentaurWeb.Storybook.Discovery do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "compass", :light, "psb:mr-1"}

  def entry("title_row"), do: [icon: {:fa, "bookmark", :thin}, name: "Title row"]

  def entry("recommendation_pennants"),
    do: [icon: {:fa, "flag-pennant", :thin}, name: "Recommendation pennant"]

  def entry("title_detail_modal"),
    do: [icon: {:fa, "window-maximize", :thin}, name: "Title detail modal"]
end
