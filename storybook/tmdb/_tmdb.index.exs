defmodule MediaCentaurWeb.Storybook.TMDB do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "clapperboard", :light, "psb:mr-1"}

  def entry("title_summary"), do: [icon: {:fa, "id-card", :thin}, name: "Title summary"]
end
