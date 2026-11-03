defmodule MediaCentaurWeb.Storybook.Watchlist do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "bookmark", :light, "psb:mr-1"}

  def entry("watchlist_row"), do: [icon: {:fa, "list", :thin}, name: "Watchlist row"]
end
