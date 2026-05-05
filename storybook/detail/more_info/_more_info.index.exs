defmodule MediaCentarrWeb.Storybook.Detail.MoreInfo do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "layer-group", :light, "psb:mr-1"}
  def folder_name, do: "More info sub-components"

  def entry("cast_grid"), do: [icon: {:fa, "user-group", :thin}, name: "Cast grid"]
  def entry("people"), do: [icon: {:fa, "users", :thin}, name: "People (linked names)"]

  def entry("external_links"),
    do: [icon: {:fa, "arrow-up-right-from-square", :thin}, name: "External links"]
end
