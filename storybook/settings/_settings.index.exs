defmodule MediaCentaurWeb.Storybook.Settings do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "sliders", :thin, "psb:mr-1"}

  def entry("settings_card"), do: [icon: {:fa, "square", :thin}, name: "Card"]
  def entry("settings_row"), do: [icon: {:fa, "toggle-on", :thin}, name: "Toggle row"]
  def entry("settings_stepper"), do: [icon: {:fa, "plus-minus", :thin}, name: "Stepper row"]
  def entry("settings_choice"), do: [icon: {:fa, "grip-lines", :thin}, name: "Choice row"]
  def entry("settings_text_row"), do: [icon: {:fa, "input-text", :thin}, name: "Text row"]
  def entry("settings_select_row"), do: [icon: {:fa, "square-caret-down", :thin}, name: "Select row"]
  def entry("settings_list"), do: [icon: {:fa, "list", :thin}, name: "List setting"]
  def entry("settings_field"), do: [icon: {:fa, "rectangle-list", :thin}, name: "Field"]
  def entry("settings_input"), do: [icon: {:fa, "i-cursor", :thin}, name: "Input"]
  def entry("settings_disclosure"), do: [icon: {:fa, "chevron-right", :thin}, name: "Disclosure"]
  def entry("path_status"), do: [icon: {:fa, "circle-check", :thin}, name: "Path status"]
  def entry("connection_row"), do: [icon: {:fa, "plug", :thin}, name: "Connection row"]
end
