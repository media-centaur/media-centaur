defmodule MediaCentaurWeb.Storybook.Status.ConsentSend do
  use PhoenixStorybook.Story, :component
  @moduledoc "Storybook coverage for the consent-flow send step (consent gate + final preview)."
  def function, do: &MediaCentaurWeb.ConsentComponents.consent_send/1

  def variations do
    [
      %Variation{
        id: :unchecked,
        attributes: %{
          consent: false,
          final_text: "[Pipeline] image download failed\n\n## Error\n…",
          target: "report-modal-component"
        }
      },
      %Variation{
        id: :checked,
        attributes: %{
          consent: true,
          final_text: "[Pipeline] image download failed\n\n## Error\n…",
          target: "report-modal-component"
        }
      }
    ]
  end
end
