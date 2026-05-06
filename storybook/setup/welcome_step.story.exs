defmodule MediaCentarrWeb.Storybook.Setup.WelcomeStep do
  @moduledoc """
  Welcome step — the first step in the Setup Tour. Greets the user,
  outlines what the tour covers, and offers a single "Begin" CTA.

  ## Contract shape

      attr :step_index, :integer, required: true
      attr :total_steps, :integer, required: true

  No probe, no content — this is a static intro page.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.SetupSteps.welcome_step/1
  def render_source, do: :function
  def layout, do: :one_column

  def variations do
    [
      %Variation{
        id: :default,
        description: "Welcome step at the start of the tour.",
        attributes: %{step_index: 1, total_steps: 8}
      }
    ]
  end
end
