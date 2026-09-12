defmodule MediaCentaurWeb.Storybook.Title do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "film", :light, "psb:mr-1"}

  # Entry keys are story filenames, which MC0009 pins to the component's
  # *function* name (`pennants/1`, `title_row/1`, `title_detail_modal/1`) —
  # not the module name. Renaming these to match the modules silently
  # breaks storybook coverage.
  def entry("pennants"), do: [icon: {:fa, "flag-pennant", :thin}, name: "Pennant"]

  def entry("sentiment_glyph"), do: [icon: {:fa, "thumbs-up", :thin}, name: "Sentiment glyph"]

  def entry("intent_control"), do: [icon: {:fa, "sliders", :thin}, name: "Intent control"]

  def entry("title_row"), do: [icon: {:fa, "bookmark", :thin}, name: "Title row"]

  def entry("title_detail_modal"),
    do: [icon: {:fa, "window-maximize", :thin}, name: "Title detail modal"]
end
