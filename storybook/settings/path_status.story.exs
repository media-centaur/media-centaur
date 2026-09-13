defmodule MediaCentaurWeb.Storybook.Settings.PathStatus do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.path_status/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :found,
        description: "The path resolves: a success tick.",
        attributes: %{path: "/usr/bin/env", kind: :executable}
      },
      %Variation{
        id: :missing,
        description: "The path does not resolve: a warning triangle with the reason in its title.",
        attributes: %{path: "/nonexistent/mpv", kind: :executable}
      }
    ]
  end
end
