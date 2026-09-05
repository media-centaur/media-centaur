defmodule MediaCentaurWeb.Storybook.Detail do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "layer-group", :light, "psb:mr-1"}

  def entry("backdrop"), do: [icon: {:fa, "panorama", :thin}, name: "Cinematic backdrop"]
  def entry("facet_strip"), do: [icon: {:fa, "table-columns", :thin}, name: "Facet strip"]
  def entry("cast_panel"), do: [icon: {:fa, "users", :thin}, name: "Cast panel"]

  def entry("cast_filter_form"), do: [icon: {:fa, "magnifying-glass", :thin}, name: "Cast filter form"]
  def entry("people"), do: [icon: {:fa, "users", :thin}, name: "People (linked names)"]

  def entry("manage_panel"), do: [icon: {:fa, "gear", :thin}, name: "Manage panel"]

  def entry("track_override_badge"), do: [icon: {:fa, "language", :thin}, name: "Track override badge"]
  def entry("metadata_row"), do: [icon: {:fa, "list", :thin}, name: "Metadata row"]
  def entry("preview_body"), do: [icon: {:fa, "file-lines", :thin}, name: "Preview body"]

  def entry("play_card"), do: [icon: {:fa, "play", :thin}, name: "Play card"]
  def entry("watched_toggle"), do: [icon: {:fa, "circle-check", :thin}, name: "Watched toggle"]

  def entry("progress_underline"), do: [icon: {:fa, "wave-pulse", :thin}, name: "Progress underline"]

  def entry("collection_rail"), do: [icon: {:fa, "film", :thin}, name: "Collection rail"]
  def entry("section"), do: [icon: {:fa, "square-dashed", :thin}, name: "Section"]
end
