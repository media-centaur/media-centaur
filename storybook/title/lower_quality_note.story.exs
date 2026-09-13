defmodule MediaCentaurWeb.Storybook.Title.LowerQualityNote do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Title.LowerQualityNote.lower_quality_note/1

  def variations do
    [
      %Variation{
        id: :accepted,
        description:
          "The per-title quality acceptance (ADR-063 §2) with its Reset. Keyed by TMDB " <>
            "identity, so it shows at any rung — including a title nobody follows. The " <>
            "library modal renders it in the Manage sheet above the file ledger; the " <>
            "title modal renders it with the tracking controls.",
        attributes: %{
          id: "lower-quality-accepted",
          ref: "tv_series-4556",
          accepted?: true
        }
      },
      %Variation{
        id: :not_accepted,
        description:
          "Unset — nothing renders. The inherited quality floor is the default and not " <>
            "a fact worth a row.",
        attributes: %{
          id: "lower-quality-unset",
          ref: "tv_series-4556",
          accepted?: false
        }
      }
    ]
  end
end
