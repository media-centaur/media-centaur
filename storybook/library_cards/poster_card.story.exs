defmodule MediaCentarrWeb.Storybook.LibraryCards.PosterCard do
  @moduledoc """
  Library grid poster card — the 2:3 thumbnail rendered by
  `MediaCentarrWeb.LibraryLive` at `/library`.

  ## Contract shape (Phase 3.1)

  After the Phase 3.1 LibraryLive cutover, the component takes a typed
  `MediaCentarr.Library.Views.BrowseItem` struct and a separate
  optional `progress` summary map:

      attr :entry, MediaCentarr.Library.Views.BrowseItem
      attr :progress, :map, default: nil

  The fixtures below construct that pair directly. The `entry` is a
  literal `%BrowseItem{}` struct so the typed-coupling check that
  Phoenix Storybook enforces (Credo MC0009) keeps the story honest
  against the component's attr typing.

  ## Variation matrix

    * Type axis — `:movie`, `:tv_series`, `:movie_series`,
      `:video_object` (each renders a different `format_type/1` label).
    * State axis — selected / playing / available toggles, plus a
      progress fraction sweep (`nil` / 25% / 75% / 100%).
    * Edge cases — missing artwork, missing `year`, `name: nil`
      (renders "Untitled"), long title (must trigger `line-clamp-2`).
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Library.Views.BrowseItem

  def function, do: &MediaCentarrWeb.Components.LibraryCards.poster_card/1
  def render_source, do: :function

  # The card's natural width is the grid's `minmax(155px, 1fr)`. The
  # template constrains the preview to that range so the previews
  # render at production size rather than stretched to column width.
  def template do
    """
    <div class="grid grid-cols-[repeat(auto-fill,minmax(155px,1fr))] gap-3 max-w-[640px]">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %VariationGroup{
        id: :type_axis,
        description:
          "Type axis — `format_type/1` produces a different footer label per " <>
            "entity kind. Each card has a poster, no progress, available, not selected.",
        variations:
          for {kind, year, suffix} <- [
                {:movie, 1922, "movie"},
                {:tv_series, 1925, "tv"},
                {:movie_series, 1920, "ms"},
                {:video_object, 1923, "vo"}
              ] do
            %Variation{
              id: String.to_atom("type_" <> suffix),
              attributes: %{
                id: "card-type-" <> suffix,
                entry: item(kind: kind, name: name_for_kind(kind), year: year, poster: true)
              }
            }
          end
      },
      %VariationGroup{
        id: :selection_states,
        description:
          "Selection axis — `selected: true` adds a primary ring. " <>
            "`playing: true` shows the pulsing dot in the top-right corner.",
        variations: [
          %Variation{
            id: :default,
            description: "Idle — no ring, no pulse.",
            attributes: %{
              id: "card-default",
              entry: item(name: "A Quiet Sample", year: 1924, poster: true)
            }
          },
          %Variation{
            id: :selected,
            description: "Selected — primary-colour ring around the card.",
            attributes: %{
              id: "card-selected",
              entry: item(name: "A Quiet Sample", year: 1924, poster: true),
              selected: true
            }
          },
          %Variation{
            id: :playing,
            description: "Playing — pulse dot in the top-right of the artwork.",
            attributes: %{
              id: "card-playing",
              entry: item(name: "A Quiet Sample", year: 1924, poster: true),
              playing: true
            }
          },
          %Variation{
            id: :selected_playing,
            description: "Both — selected ring + playing pulse simultaneously.",
            attributes: %{
              id: "card-selected-playing",
              entry: item(name: "A Quiet Sample", year: 1924, poster: true),
              selected: true,
              playing: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :progress_axis,
        description:
          "Progress bar fills the bottom edge of the artwork at the computed " <>
            "fraction. `progress: nil` and 0% both suppress the bar.",
        variations: [
          %Variation{
            id: :no_progress,
            description: "No progress record — bar suppressed.",
            attributes: %{
              id: "card-progress-none",
              entry: item(name: "Sample Show", year: 1923, poster: true),
              progress: nil
            }
          },
          %Variation{
            id: :early,
            description: "25% complete.",
            attributes: %{
              id: "card-progress-early",
              entry: item(name: "Sample Show", year: 1923, poster: true),
              progress: progress(25)
            }
          },
          %Variation{
            id: :midway,
            description: "75% complete.",
            attributes: %{
              id: "card-progress-mid",
              entry: item(name: "Sample Show", year: 1923, poster: true),
              progress: progress(75)
            }
          },
          %Variation{
            id: :complete,
            description: "100% complete — bar reaches the right edge.",
            attributes: %{
              id: "card-progress-full",
              entry: item(name: "Sample Show", year: 1923, poster: true),
              progress: progress(100)
            }
          }
        ]
      },
      %VariationGroup{
        id: :artwork_states,
        description:
          "Artwork resolution — has-poster vs no-poster (placeholder film " <>
            "icon) vs `available: false` (storage offline; artwork hidden " <>
            "behind a quiet neutral block).",
        variations: [
          %Variation{
            id: :no_artwork,
            description: "BrowseItem.poster_url is nil — film placeholder fills the frame.",
            attributes: %{
              id: "card-no-art",
              entry: item(name: "No Artwork Sample", year: 1922, poster: false)
            }
          },
          %Variation{
            id: :unavailable,
            description:
              "`available: false` — artwork is suppressed behind a neutral " <>
                "block (storage offline). The footer text remains.",
            attributes: %{
              id: "card-unavailable",
              entry: item(name: "Offline Sample", year: 1922, poster: true),
              available: false
            }
          }
        ]
      },
      %VariationGroup{
        id: :edge_cases,
        description: "Title and metadata edge cases.",
        variations: [
          %Variation{
            id: :long_title,
            description:
              "Long title — `line-clamp-2` truncates after the second line " <>
                "without pushing the year off the card.",
            attributes: %{
              id: "card-long-title",
              entry:
                item(
                  name: "An Extraordinarily Long Sample Title That Definitely Exceeds The Footer Width",
                  year: 1924,
                  poster: true
                )
            }
          },
          %Variation{
            id: :no_year,
            description:
              "`year: nil` — the year and the leading `·` separator are " <>
                "suppressed; only the type label renders in the footer.",
            attributes: %{
              id: "card-no-year",
              entry: item(name: "Sample Without Year", year: nil, poster: true)
            }
          },
          %Variation{
            id: :untitled,
            description: "`name: nil` — footer falls back to the literal `\"Untitled\"`.",
            attributes: %{
              id: "card-untitled",
              entry: item(name: nil, year: 1922, poster: true)
            }
          }
        ]
      }
    ]
  end

  # --- Fixtures ----------------------------------------------------------

  defp item(opts) do
    kind = Keyword.get(opts, :kind, :movie)
    name = Keyword.get(opts, :name, "Sample Show")
    year = Keyword.get(opts, :year, 1922)
    poster? = Keyword.get(opts, :poster, true)

    %BrowseItem{
      id:
        "entity-" <>
          Atom.to_string(kind) <> "-" <> Integer.to_string(:erlang.phash2(name)),
      kind: kind,
      name: name,
      date_published: year && Date.new!(year, 1, 1),
      year: year,
      poster_url: poster? && "/storybook/fixtures/poster.jpg",
      present?: true,
      rank: 0
    }
  end

  # Builds a ProgressSummary-shaped map at the given completion percentage.
  # The component reads only `:episode_position_seconds` and
  # `:episode_duration_seconds`; the other fields are included for
  # shape-realism.
  defp progress(percent) do
    duration = 1800.0
    position = duration * percent / 100.0

    %{
      current_episode: nil,
      episode_position_seconds: position,
      episode_duration_seconds: duration,
      episodes_completed: 0,
      episodes_total: 1
    }
  end

  defp name_for_kind(:movie), do: "Sample Movie"
  defp name_for_kind(:tv_series), do: "Sample TV Show"
  defp name_for_kind(:movie_series), do: "Sample Movie Series"
  defp name_for_kind(:video_object), do: "Sample Video"
end
