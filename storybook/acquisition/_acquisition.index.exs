defmodule MediaCentarrWeb.Storybook.Acquisition do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "arrow-down-to-bracket", :light, "psb:mr-1"}

  def entry("pursuit_row"), do: [icon: {:fa, "list-tree", :thin}, name: "Pursuit row"]
  def entry("pursuit_header"), do: [icon: {:fa, "heading", :thin}, name: "Pursuit header"]
  def entry("timeline"), do: [icon: {:fa, "timeline", :thin}, name: "Pursuit timeline"]
  def entry("decision_card"), do: [icon: {:fa, "wand-magic-sparkles", :thin}, name: "Decision card"]

  def entry("queue_status_badge"), do: [icon: {:fa, "signal-stream", :thin}, name: "Queue status badge"]
end
