defmodule MediaCentaurWeb.Storybook.Status.ConsentIntro do
  use PhoenixStorybook.Story, :component
  @moduledoc "Storybook coverage for the consent-flow intro step (promises + optional narrative)."
  def function, do: &MediaCentaurWeb.ConsentComponents.consent_intro/1

  def variations do
    [
      %Variation{
        id: :empty,
        attributes: %{narrative: "", target: "report-modal-component"}
      },
      %Variation{
        id: :with_text,
        attributes: %{narrative: "It froze when I pressed play.", target: "report-modal-component"}
      }
    ]
  end
end
