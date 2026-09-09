defmodule MediaCentaurWeb.Storybook.Discovery do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "compass", :light, "psb:mr-1"}

  def entry("title_row"), do: [icon: {:fa, "bookmark", :thin}, name: "Title row"]

  def entry("person_card"), do: [icon: {:fa, "user", :thin}, name: "Person card"]

  def entry("intent_control"), do: [icon: {:fa, "sliders", :thin}, name: "Intent control"]

  def entry("title_detail_modal"),
    do: [icon: {:fa, "window-maximize", :thin}, name: "Title detail modal"]
end
