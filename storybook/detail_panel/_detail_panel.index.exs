defmodule MediaCentarrWeb.Storybook.DetailPanel do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "rectangle-list", :light, "psb:mr-1"}

  def entry("detail_panel"), do: [icon: {:fa, "id-card", :thin}, name: "Detail panel"]
end
