defmodule MediaCentaurWeb.Storybook.AppCards do
  use PhoenixStorybook.Index

  def entry("banner_card"), do: [icon: {:fa, "rocket-launch", :thin}, name: "App banner card"]
  def entry("banner_art"), do: [icon: {:fa, "image", :thin}, name: "App banner art"]
end
