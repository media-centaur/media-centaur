defmodule MediaCentarrWeb.Storybook.Composites do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "object-group", :light, "psb:mr-1"}

  def entry("modal_shell"), do: [icon: {:fa, "window-maximize", :thin}, name: "Modal shell"]
  def entry("hero_card"), do: [icon: {:fa, "id-card", :thin}, name: "Hero card"]
end
