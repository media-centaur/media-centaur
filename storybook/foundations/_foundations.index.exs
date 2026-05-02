defmodule MediaCentarrWeb.Storybook.Foundations do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "swatchbook", :light, "psb:mr-1"}
  def folder_index, do: 0

  def entry("colors"), do: [icon: {:fa, "palette", :thin}, name: "Colors"]
  def entry("typography"), do: [icon: {:fa, "text-size", :thin}, name: "Typography"]
  def entry("spacing"), do: [icon: {:fa, "ruler-combined", :thin}, name: "Spacing & surfaces"]
  def entry("uidr_index"), do: [icon: {:fa, "list-tree", :thin}, name: "UIDR index"]
end
