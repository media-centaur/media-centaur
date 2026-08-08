defmodule MediaCentaurWeb.Storybook.Detail do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "layer-group", :light, "psb:mr-1"}

  def entry("cinematic_backdrop"), do: [icon: {:fa, "panorama", :thin}, name: "Cinematic backdrop"]
  def entry("facet_strip"), do: [icon: {:fa, "table-columns", :thin}, name: "Facet strip"]
  def entry("cast_panel"), do: [icon: {:fa, "users", :thin}, name: "Cast panel"]
  def entry("cast_grid"), do: [icon: {:fa, "user-group", :thin}, name: "Cast grid"]
  def entry("people"), do: [icon: {:fa, "users", :thin}, name: "People (linked names)"]

  def entry("track_override_badge"), do: [icon: {:fa, "language", :thin}, name: "Track override badge"]
  def entry("metadata_row"), do: [icon: {:fa, "list", :thin}, name: "Metadata row"]

  def entry("play_card"), do: [icon: {:fa, "play", :thin}, name: "Play card"]
  def entry("section"), do: [icon: {:fa, "square-dashed", :thin}, name: "Section"]
  def entry("hero"), do: [icon: {:fa, "image", :thin}, name: "Hero"]
end
