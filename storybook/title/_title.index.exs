defmodule MediaCentaurWeb.Storybook.Title do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "film", :light, "psb:mr-1"}

  def entry("pennant"), do: [icon: {:fa, "flag-pennant", :thin}, name: "Pennant"]

  def entry("intent_control"), do: [icon: {:fa, "sliders", :thin}, name: "Intent control"]
end
