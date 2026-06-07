defmodule MediaCentaurWeb.Storybook.LibraryOverview do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "layer-group", :light, "psb:mr-1"}

  def entry("glance_card"), do: [icon: {:fa, "chart-simple", :thin}, name: "Glance card"]
  def entry("pending_work_card"), do: [icon: {:fa, "list-check", :thin}, name: "Pending work card"]

  def entry("completeness_card"), do: [icon: {:fa, "puzzle-piece", :thin}, name: "Completeness card"]

  def entry("storage_outlook_card"), do: [icon: {:fa, "hard-drive", :thin}, name: "Storage outlook card"]
end
