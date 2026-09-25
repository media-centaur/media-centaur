defmodule MediaCentaurWeb.Storybook.Discovery do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "compass", :light, "psb:mr-1"}

  def entry("feed_band"), do: [icon: {:fa, "stream", :thin}, name: "Feed band"]
  def entry("identity_tile"), do: [icon: {:fa, "circle-user", :thin}, name: "Identity tile"]
  def entry("person_card"), do: [icon: {:fa, "user", :thin}, name: "Person card"]
end
