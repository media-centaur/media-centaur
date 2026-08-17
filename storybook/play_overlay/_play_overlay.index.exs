defmodule MediaCentaurWeb.Storybook.PlayOverlay do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "circle-play", :light, "psb:mr-1"}

  def entry("play_overlay"), do: [icon: {:fa, "play", :thin}, name: "Play overlay"]
end
