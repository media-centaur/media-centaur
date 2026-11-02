defmodule MediaCentaurWeb.Storybook.Incoming do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "inbox", :light, "psb:mr-1"}

  def entry("ledger"), do: [icon: {:fa, "clock-rotate-left", :thin}, name: "History archive"]
end
