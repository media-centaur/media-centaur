defmodule MediaCentaurWeb.Storybook.Acquisition do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "arrow-down-to-bracket", :light, "psb:mr-1"}

  def entry("media_omnibox"), do: [icon: {:fa, "magnifying-glass", :thin}, name: "Media omnibox"]

  def entry("title_result_summary"),
    do: [icon: {:fa, "clapperboard", :thin}, name: "Title result summary"]

  def entry("plan_modal"), do: [icon: {:fa, "chess-board", :thin}, name: "Plan modal"]
  def entry("pursuit_row"), do: [icon: {:fa, "list-tree", :thin}, name: "Pursuit row"]
  def entry("pursuit_group"), do: [icon: {:fa, "layer-group", :thin}, name: "Pursuit group"]
  def entry("pursuit_header"), do: [icon: {:fa, "heading", :thin}, name: "Pursuit header"]
  def entry("pursuit_modal"), do: [icon: {:fa, "rectangle-history", :thin}, name: "Pursuit modal"]
  def entry("unit_board"), do: [icon: {:fa, "table-cells", :thin}, name: "Unit board"]
  def entry("timeline"), do: [icon: {:fa, "timeline", :thin}, name: "Pursuit timeline"]
  def entry("decision_card"), do: [icon: {:fa, "wand-magic-sparkles", :thin}, name: "Decision card"]

  def entry("connectivity_badge"), do: [icon: {:fa, "signal-stream", :thin}, name: "Connectivity badge"]
end
