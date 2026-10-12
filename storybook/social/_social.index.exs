defmodule MediaCentaurWeb.Storybook.Social do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "users", :light, "psb:mr-1"}

  def entry("crop_previews"), do: [icon: {:fa, "crop", :thin}, name: "Crop previews"]
  def entry("feed_row"), do: [icon: {:fa, "stream", :thin}, name: "Feed row"]
  def entry("hidden_person_row"), do: [icon: {:fa, "eye-slash", :thin}, name: "Hidden person row"]
  def entry("hue_swatches"), do: [icon: {:fa, "palette", :thin}, name: "Hue swatches"]
  def entry("identity_tile"), do: [icon: {:fa, "circle-user", :thin}, name: "Identity tile"]
  def entry("person_card"), do: [icon: {:fa, "user", :thin}, name: "Person card"]
end
