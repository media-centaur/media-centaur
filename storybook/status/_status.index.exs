defmodule MediaCentaurWeb.Storybook.Status do
  use PhoenixStorybook.Index

  def folder_open?, do: false
  def folder_icon, do: {:fa, "chart-line", :light, "psb:mr-1"}

  def entry("issue_view"), do: [icon: {:fa, "circle-exclamation", :thin}, name: "Issue view"]
  def entry("consent_intro"), do: [icon: {:fa, "shield-check", :thin}, name: "Consent intro"]
  def entry("consent_review"), do: [icon: {:fa, "magnifying-glass", :thin}, name: "Consent review"]
  def entry("consent_send"), do: [icon: {:fa, "paper-plane", :thin}, name: "Consent send"]
  def entry("library_widget"), do: [icon: {:fa, "layer-group", :thin}, name: "Library widget"]
  def entry("watcher_widget"), do: [icon: {:fa, "folder-tree", :thin}, name: "Watcher widget"]
  def entry("pipeline_widget"), do: [icon: {:fa, "diagram-project", :thin}, name: "Pipeline widget"]
  def entry("tmdb_widget"), do: [icon: {:fa, "film", :thin}, name: "TMDB widget"]
  def entry("playback_widget"), do: [icon: {:fa, "play", :thin}, name: "Playback widget"]
  def entry("social_widget"), do: [icon: {:fa, "users", :thin}, name: "Social widget"]

  def entry("self_update_widget"), do: [icon: {:fa, "arrow-down-to-line", :thin}, name: "Updates widget"]
end
