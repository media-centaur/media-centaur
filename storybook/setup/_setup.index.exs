defmodule MediaCentarrWeb.Storybook.Setup do
  use PhoenixStorybook.Index

  def folder_open?, do: true
  def folder_icon, do: {:fa, "compass", :light, "psb:mr-1"}

  def entry("binary_step"), do: [icon: {:fa, "terminal", :thin}, name: "Binary step (mpv / ffprobe)"]

  def entry("integration_step"),
    do: [icon: {:fa, "plug", :thin}, name: "Integration step (TMDB / Prowlarr)"]

  def entry("watch_dirs_step"), do: [icon: {:fa, "folder-open", :thin}, name: "Watch directories step"]
end
