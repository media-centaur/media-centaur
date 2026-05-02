defmodule MediaCentarrWeb.Storybook.LibraryCards do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "table-cells", :light, "psb:mr-1"}

  def entry("poster_card"), do: [icon: {:fa, "image", :thin}, name: "Poster card"]
  def entry("toolbar"), do: [icon: {:fa, "sliders", :thin}, name: "Toolbar"]
end
