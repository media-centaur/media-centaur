defmodule MediaCentaurWeb.Storybook.CoreComponents do
  use PhoenixStorybook.Index

  def folder_open?, do: true

  def entry("action_toast"), do: [icon: {:fa, "rotate-left", :thin}, name: "Action toast"]
  def entry("badge"), do: [icon: {:fa, "tag", :thin}]
  def entry("button"), do: [icon: {:fa, "rectangle-ad", :thin}]
  def entry("empty_state"), do: [icon: {:fa, "wind", :thin}, name: "Empty state"]
  def entry("flash"), do: [icon: {:fa, "bolt", :thin}]
  def entry("header"), do: [icon: {:fa, "heading", :thin}]
  def entry("icon"), do: [icon: {:fa, "icons", :thin}]
  def entry("input"), do: [icon: {:fa, "input-text", :thin}]
  def entry("list"), do: [icon: {:fa, "list", :thin}]
  def entry("menu_list"), do: [icon: {:fa, "list-ul", :thin}, name: "Menu list"]
  def entry("menu_select"), do: [icon: {:fa, "square-caret-down", :thin}, name: "Menu select"]
  def entry("modal"), do: [icon: {:fa, "window-maximize", :thin}]
  def entry("segmented_control"), do: [icon: {:fa, "grip-lines", :thin}, name: "Segmented control"]
  def entry("split_button"), do: [icon: {:fa, "square-caret-down", :thin}, name: "Split button"]
  def entry("table"), do: [icon: {:fa, "table", :thin}]
end
