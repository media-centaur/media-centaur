defmodule MediaCentaurWeb.Storybook.ViewingLayer do
  use PhoenixStorybook.Index

  def folder_icon, do: {:fa, "tv", :thin}
  def folder_name, do: "Viewing layer"

  def entry("viewing_layer"), do: [name: "Viewing layer", icon: {:fa, "tv", :thin}]
end
