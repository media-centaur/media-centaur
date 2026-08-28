defmodule MediaCentaurWeb.Storybook.AppCards do
  use PhoenixStorybook.Index

  def entry("banner_card"), do: [icon: {:fa, "rocket-launch", :thin}, name: "App banner card"]
end
