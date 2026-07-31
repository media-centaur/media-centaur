defmodule MediaCentaurWeb.Storybook.Acquisition.MediaOmnibox do
  @moduledoc """
  The Downloads hero search (UIDR-014) — one surface, two modes. Media
  mode asks "What do you want to watch?" with a TMDB type-ahead
  dropdown; release mode flips the same box into the brace-expansion
  query form (its results render below the hero, outside this
  component).
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ReleaseTracking.TitleResult
  alias MediaCentaurWeb.IncomingLive.SearchSession

  def function, do: &MediaCentaurWeb.Components.Acquisition.MediaOmnibox.media_omnibox/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl relative min-h-[34rem]">
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
        id: :media_suggestions,
        description:
          "Focused with nothing typed — library shows not yet tracked surface as one-click " <>
            "Track cards in the overlay (the retired Track modal's suggestion strip, folded " <>
            "into the one search surface). A confirmed card flips to Tracking.",
        attributes: %{
          mode: :media,
          results_open: true,
          suggestions: [
            %MediaCentaurWeb.Components.Acquisition.MediaOmnibox.Suggestion{
              tv_series_id: 1,
              tmdb_id: "246810",
              name: "Sample Show",
              media_type: :tv_series,
              poster_url: nil
            },
            %MediaCentaurWeb.Components.Acquisition.MediaOmnibox.Suggestion{
              tv_series_id: 2,
              tmdb_id: "246811",
              name: "Sample Show Two",
              media_type: :tv_series,
              poster_url: nil
            }
          ],
          confirmed_ids: {:eval, ~s|MapSet.new(["246811"])|}
        }
      },
      %Variation{
        id: :media_results,
        description:
          "Typed query with TMDB results — the floating spotlight overlay. The top " <>
            "relevance hit fills the spotlight pane by default (poster, overview, primary " <>
            "action); the list scrolls beside it. Poster paths are fake, so thumbnails " <>
            "render broken outside the app; the icon fallback shows the no-poster treatment.",
        attributes: %{
          mode: :media,
          query: "sample",
          results: [
            %TitleResult{
              tmdb_id: 246_810,
              media_type: :tv_series,
              name: "Sample Show",
              year: "2010",
              poster_path: "/sample-show-poster.jpg",
              overview: "A sample overview line that helps confirm this is the show you meant.",
              tracked?: true
            },
            %TitleResult{
              tmdb_id: 777,
              media_type: :movie,
              name: "Sample Movie",
              year: "2010",
              overview: "A sample movie overview."
            },
            %TitleResult{
              tmdb_id: 778,
              media_type: :movie,
              name: "Sample Movie Returns: An Extraordinarily Long Title That Truncates",
              year: "2012"
            }
          ]
        }
      },
      %Variation{
        id: :media_results_preview_swapped,
        description:
          "A non-top result previewed in the spotlight (mouse hover and d-pad focus both " <>
            "swap the pane) — its list row carries the active highlight.",
        attributes: %{
          mode: :media,
          query: "sample",
          preview_id: {:movie, 777},
          results: [
            %TitleResult{
              tmdb_id: 246_810,
              media_type: :tv_series,
              name: "Sample Show",
              year: "2010",
              overview: "A sample overview line."
            },
            %TitleResult{
              tmdb_id: 777,
              media_type: :movie,
              name: "Sample Movie",
              year: "2010",
              overview: "The previewed movie's overview, shown while its row is hovered."
            }
          ]
        }
      },
      %Variation{
        id: :media_results_long,
        description:
          "A full TMDB page (20 results) — the dropdown caps its height " <>
            "and scrolls instead of paginating.",
        attributes: %{
          mode: :media,
          query: "sample",
          results:
            for n <- 1..20 do
              %TitleResult{
                tmdb_id: 1000 + n,
                media_type: if(rem(n, 3) == 0, do: :tv_series, else: :movie),
                name: "Sample Title #{n}",
                year: "#{2000 + n}"
              }
            end
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
