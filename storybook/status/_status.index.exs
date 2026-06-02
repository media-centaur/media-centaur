defmodule MediaCentaurWeb.Storybook.Status do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "chart-line", :light, "psb:mr-1"}

  def entry("consent_intro"), do: [icon: {:fa, "shield-check", :thin}, name: "Consent intro"]
  def entry("consent_review"), do: [icon: {:fa, "magnifying-glass", :thin}, name: "Consent review"]
  def entry("consent_send"), do: [icon: {:fa, "paper-plane", :thin}, name: "Consent send"]
  def entry("watcher_widget"), do: [icon: {:fa, "folder-tree", :thin}, name: "Watcher widget"]
end
