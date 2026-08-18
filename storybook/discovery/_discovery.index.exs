defmodule MediaCentaurWeb.Storybook.Discovery do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "compass", :light, "psb:mr-1"}

  def entry("watchlist_row"), do: [icon: {:fa, "bookmark", :thin}, name: "Watchlist row"]
end
