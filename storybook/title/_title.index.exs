defmodule MediaCentaurWeb.Storybook.Title do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "film", :light, "psb:mr-1"}

  # Entry keys are story filenames, which MC0009 pins to the component's
  # *function* name (`social_glyph/1`, `title_row/1`) —
  # not the module name. Renaming these to match the modules silently
  # breaks storybook coverage.
  def entry("social_glyph"), do: [icon: {:fa, "heart", :thin}, name: "Social glyph"]

  def entry("social_glyphs"), do: [icon: {:fa, "icons", :thin}, name: "Social glyphs"]

  def entry("social_capsule"), do: [icon: {:fa, "capsules", :thin}, name: "Social capsule"]

  def entry("social_panel"), do: [icon: {:fa, "comments", :thin}, name: "Social panel"]

  def entry("refresh_from_tmdb"), do: [icon: {:fa, "cloud-arrow-down", :thin}, name: "Refresh from TMDB"]

  def entry("tracking_controls"), do: [icon: {:fa, "sliders", :thin}, name: "Tracking controls"]

  def entry("title_row"), do: [icon: {:fa, "bookmark", :thin}, name: "Title row"]
end
