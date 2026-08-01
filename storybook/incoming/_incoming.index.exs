defmodule MediaCentaurWeb.Storybook.Incoming do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "inbox", :light, "psb:mr-1"}

  def entry("status_pill"), do: [icon: {:fa, "tag", :thin}, name: "Status pill"]
  def entry("shelf"), do: [icon: {:fa, "list", :thin}, name: "Coming up shelf"]
  def entry("shelf_row"), do: [icon: {:fa, "list", :thin}, name: "Shelf row"]
  def entry("ledger"), do: [icon: {:fa, "clock-rotate-left", :thin}, name: "Landed ledger"]
end
