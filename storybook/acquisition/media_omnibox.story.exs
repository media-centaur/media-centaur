defmodule MediaCentaurWeb.Storybook.Acquisition.MediaOmnibox do
  @moduledoc """
  The Downloads hero search (UIDR-014) — one surface, two modes. Media
  mode asks "What do you want to watch?" with a TMDB type-ahead
  dropdown; release mode flips the same box into the brace-expansion
  query form (its results render below the hero, outside this
  component).
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.AcquisitionLive.SearchSession
  alias MediaCentaurWeb.Components.Acquisition.MediaOmnibox

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
        id: :media_results,
        description:
          "Typed query with TMDB results — poster thumbnail (fake path, renders broken " <>
            "outside the app), icon fallback, type chips, years, a tracked annotation.",
        attributes: %{
          mode: :media,
          query: "sample",
          results: [
            %MediaOmnibox.Result{
              tmdb_id: 246_810,
              media_type: :tv_series,
              name: "Sample Show",
              year: "2010",
              poster_path: "/sample-show-poster.jpg",
              tracked?: true
            },
            %MediaOmnibox.Result{
              tmdb_id: 777,
              media_type: :movie,
              name: "Sample Movie",
              year: "2010"
            },
            %MediaOmnibox.Result{
              tmdb_id: 778,
              media_type: :movie,
              name: "Sample Movie Returns: An Extraordinarily Long Title That Truncates",
              year: "2012"
            }
          ]
        }
      },
      %Variation{
        id: :media_searching,
        description: "Type-ahead in flight.",
        attributes: %{mode: :media, query: "sample", searching?: true}
      },
      %Variation{
        id: :media_no_results,
        description: "The honest empty answer.",
        attributes: %{mode: :media, query: "zzzzz", results: []}
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
      }
    ]
  end
end
