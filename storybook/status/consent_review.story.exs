defmodule MediaCentaurWeb.Storybook.Status.ConsentReview do
  use PhoenixStorybook.Story, :component

  @moduledoc "Storybook coverage for the consent-flow review step (editable title + body, privacy notice)."
  def function, do: &MediaCentaurWeb.ConsentComponents.consent_review/1

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{
          title: "[Pipeline] image download failed",
          body: "## Environment\nApp: media-centaur 0.77.7\n\n## Error\nFingerprint: abc123\n",
          target: "report-modal-component"
        }
      },
      %Variation{
        id: :edited,
        attributes: %{
          title: "[Pipeline] image download failed",
          body: "## Environment\nApp: media-centaur 0.77.7\n\n## Error\n",
          target: "report-modal-component"
        }
      }
    ]
  end
end
