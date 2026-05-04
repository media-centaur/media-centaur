defmodule MediaCentarrWeb.Storybook.Detail do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "layer-group", :light, "psb:mr-1"}

  def entry("facet_strip"), do: [icon: {:fa, "table-columns", :thin}, name: "Facet strip"]
  def entry("more_info_panel"), do: [icon: {:fa, "users", :thin}, name: "More info panel"]
  def entry("metadata_row"), do: [icon: {:fa, "list", :thin}, name: "Metadata row"]
  def entry("play_card"), do: [icon: {:fa, "play", :thin}, name: "Play card"]
  def entry("section"), do: [icon: {:fa, "square-dashed", :thin}, name: "Section"]
  def entry("hero"), do: [icon: {:fa, "image", :thin}, name: "Hero"]
end
