defmodule MediaCentarrWeb.Storybook.Setup do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "compass", :light, "psb:mr-1"}

  def entry("welcome_step"), do: [icon: {:fa, "hand-wave", :thin}, name: "Welcome step", index: 1]

  def entry("watch_dirs_step"),
    do: [icon: {:fa, "folder-open", :thin}, name: "Watch directories step", index: 2]

  def entry("binary_step"),
    do: [icon: {:fa, "terminal", :thin}, name: "Binary step (mpv / ffprobe)", index: 3]

  def entry("integration_step"),
    do: [icon: {:fa, "plug", :thin}, name: "Integration step (TMDB / Prowlarr)", index: 4]

  def entry("summary_step"), do: [icon: {:fa, "list-check", :thin}, name: "Summary step", index: 5]
end
