defmodule MediaCentaurWeb.Storybook.Navigation do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "signs-post", :light, "psb:mr-1"}

  def entry("tab_strip"), do: [icon: {:fa, "folder-tree", :thin}, name: "Tab strip"]
end
