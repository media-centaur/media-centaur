defmodule MediaCentaurWeb.Storybook.Acquisition.MediaOmnibox do
  @moduledoc """
  The Downloads hero search (UIDR-014) — one surface, two modes. Media
  mode asks "What do you want to watch?"; release mode flips the same
  box into the brace-expansion query form. Both modes answer flat,
  below the hero, outside this component (media: the MediaResults
  section; release: the search zone).
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.IncomingLive.SearchSession

  def function, do: &MediaCentaurWeb.Components.Acquisition.MediaOmnibox.media_omnibox/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :media_resting,
        description: "Fresh page — media mode, nothing typed, the release-mode flip bottom right.",
        attributes: %{mode: :media}
      },
      %Variation{
        id: :release_mode,
        description:
          "The flipped box — monospace brace-expansion input (Enter to search, no button), " <>
            "syntax hint, expansion preview, and the way back to media mode.",
        attributes: %{
          mode: :release,
          session: %SearchSession{
            query: "Sample Show S01E{01-04}",
            expansion_preview: {:ok, 4}
          }
        }
      },
      %Variation{
        id: :release_invalid_syntax,
        description:
          "Invalid braces — error-colored preview; Enter still submits (submit_search guards server-side).",
        attributes: %{
          mode: :release,
          session: %SearchSession{
            # An unbalanced literal `{` breaks storybook's HEEx attr
            # serialization (naive brace counting) — stand in with a
            # brace-free malformed query; the preview carries the error.
            query: "Sample Show S01E01-",
            expansion_preview: {:error, :invalid_syntax}
          }
        }
      },
      %VariationGroup{
        id: :hero,
        description:
          "Hero mode — the Incoming page's front door. Centered column without the card " <>
            "chrome, prompt line above a taller input, and the mode hint below with the " <>
            "active mode emphasized (the inactive name is the flip control — same " <>
            "omnibox_mode event as the corner toggle). Default (hero: false) renders " <>
            "exactly as the variations above.",
        variations: [
          %Variation{
            id: :hero_media,
            attributes: %{mode: :media, hero: true}
          },
          %Variation{
            id: :hero_release,
            attributes: %{
              mode: :release,
              hero: true,
              session: %SearchSession{
                query: "Nosferatu 1922 {720p,1080p}",
                expansion_preview: {:ok, 2}
              }
            }
          }
        ]
      }
    ]
  end
end
