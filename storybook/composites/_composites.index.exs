defmodule MediaCentaurWeb.Storybook.Composites do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "object-group", :light, "psb:mr-1"}

  def entry("cinematic_shell"), do: [icon: {:fa, "window-maximize", :thin}, name: "Cinematic shell"]
  def entry("hero_card"), do: [icon: {:fa, "id-card", :thin}, name: "Hero card"]

  def entry("progress_hairline"), do: [icon: {:fa, "wave-square", :thin}, name: "Progress hairline"]
end
