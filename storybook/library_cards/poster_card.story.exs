defmodule MediaCentarrWeb.Storybook.LibraryCards.PosterCard do
  @moduledoc """
  Library grid poster card — the 2:3 thumbnail used on `/` (Library page).

  ## Contract shape (untyped today — see contract plan)

  The component takes `attr :entry, :map, required: true`. The map shape
  the grid streams into the card is:

      %{
        entity: %{
          id: term(),
          name: String.t() | nil,
          type: :movie | :tv_series | :movie_series | :video_object,
          date_published: String.t() | nil,   # "YYYY-MM-DD" or "YYYY"
          images: [%{role: String.t(), content_url: String.t()}]
        },
        progress: ProgressSummary.t() | nil
        # progress_records: [...]              # not used by poster_card
      }

  The fixtures below construct that shape directly with literal maps —
  no factories, no Ecto schemas. This is deliberate: the migration to
  a typed `LibraryEntry` view-model is **Phase 3** of the component
  contract plan (`~/src/media-centarr/component-contract-plan.md`),
  which moves `library_cards.ex` and `upcoming_cards.ex` to a shared
  `MediaCentarrWeb.ViewModels.*` namespace as a single PR. Doing it
  one-component-at-a-time would either create a one-off type that gets
  renamed in Phase 3, or pre-empt a design that needs both call sites
  to inform it.

  Once Phase 3 lands, this story flips to literal struct fixtures.

  ## Variation matrix

    * Type axis — `:movie`, `:tv_series`, `:movie_series`, `:video_object`
      (each renders a different `format_type/1` label).
    * State axis — selected / playing / available toggles, plus a
      progress fraction sweep (`nil` / 25% / 75% / 100%).
    * Edge cases — missing artwork, missing `date_published`, `name: nil`
      (renders "Untitled"), long title (must trigger `line-clamp-2`).
  """

  use PhoenixStorybook.Story, :component

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
            "entity type. Each card has a poster but no progress, available, not selected.",
        variations:
          for {type, year, suffix} <- [
                {:movie, "1922-09-04", "movie"},
                {:tv_series, "1925-04-15", "tv"},
                {:movie_series, "1920-01-01", "ms"},
                {:video_object, "1923-06-12", "vo"}
              ] do
            %Variation{
              id: String.to_atom("type_" <> suffix),
              attributes: %{
                id: "card-type-" <> suffix,
                entry: entry(type: type, name: name_for_type(type), date: year, poster: true)
              }
            }
          end
      },
      %VariationGroup{
        id: :selection_states,
        description:
          "Selection axis — `selected: true` adds a primary ring. `playing: true` " <>
            "shows the pulsing dot in the top-right corner.",
        variations: [
          %Variation{
            id: :default,
            description: "Idle — no ring, no pulse.",
            attributes: %{
              id: "card-default",
              entry: entry(name: "A Quiet Sample", date: "1924-03-08", poster: true)
            }
          },
          %Variation{
            id: :selected,
            description: "Selected — primary-colour ring around the card.",
            attributes: %{
              id: "card-selected",
              entry: entry(name: "A Quiet Sample", date: "1924-03-08", poster: true),
              selected: true
            }
          },
          %Variation{
            id: :playing,
            description: "Playing — pulse dot in the top-right of the artwork.",
            attributes: %{
              id: "card-playing",
              entry: entry(name: "A Quiet Sample", date: "1924-03-08", poster: true),
              playing: true
            }
          },
          %Variation{
            id: :selected_playing,
            description: "Both — selected ring + playing pulse simultaneously.",
            attributes: %{
              id: "card-selected-playing",
              entry: entry(name: "A Quiet Sample", date: "1924-03-08", poster: true),
              selected: true,
              playing: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :progress_axis,
        description:
          "Progress bar fills bottom-edge of the artwork at the computed fraction. " <>
            "`progress: nil` and 0% both suppress the bar.",
        variations: [
          %Variation{
            id: :no_progress,
            description: "No progress record — bar suppressed.",
            attributes: %{
              id: "card-progress-none",
              entry: entry(name: "Sample Show", date: "1923-06-12", poster: true, progress: nil)
            }
          },
          %Variation{
            id: :early,
            description: "25% complete.",
            attributes: %{
              id: "card-progress-early",
              entry:
                entry(
                  name: "Sample Show",
                  date: "1923-06-12",
                  poster: true,
                  progress: progress(25)
                )
            }
          },
          %Variation{
            id: :midway,
            description: "75% complete.",
            attributes: %{
              id: "card-progress-mid",
              entry:
                entry(
                  name: "Sample Show",
                  date: "1923-06-12",
                  poster: true,
                  progress: progress(75)
                )
            }
          },
          %Variation{
            id: :complete,
            description: "100% complete — bar reaches the right edge.",
            attributes: %{
              id: "card-progress-full",
              entry:
                entry(
                  name: "Sample Show",
                  date: "1923-06-12",
                  poster: true,
                  progress: progress(100)
                )
            }
          }
        ]
      },
      %VariationGroup{
        id: :artwork_states,
        description:
          "Artwork resolution — has-poster vs no-poster (placeholder film icon) " <>
            "vs `available: false` (storage offline; artwork hidden behind a quiet " <>
            "neutral block).",
        variations: [
          %Variation{
            id: :no_artwork,
            description: "Entity has no `\"poster\"` image — film placeholder fills the frame.",
            attributes: %{
              id: "card-no-art",
              entry: entry(name: "No Artwork Sample", date: "1922-09-04", poster: false)
            }
          },
          %Variation{
            id: :unavailable,
            description:
              "`available: false` — artwork is suppressed behind a neutral block " <>
                "(storage offline). The footer text remains.",
            attributes: %{
              id: "card-unavailable",
              entry: entry(name: "Offline Sample", date: "1922-09-04", poster: true),
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
              "Long title — `line-clamp-2` should truncate after the second line " <>
                "and not push the year metadata off the card.",
            attributes: %{
              id: "card-long-title",
              entry:
                entry(
                  name: "An Extraordinarily Long Sample Title That Definitely Exceeds The Footer Width",
                  date: "1924-03-08",
                  poster: true
                )
            }
          },
          %Variation{
            id: :no_date,
            description:
              "`date_published: nil` — the year and the leading `·` separator are " <>
                "suppressed; only the type label renders in the footer.",
            attributes: %{
              id: "card-no-date",
              entry: entry(name: "Sample Without Year", date: nil, poster: true)
            }
          },
          %Variation{
            id: :untitled,
            description: "`name: nil` — footer falls back to the literal `\"Untitled\"`.",
            attributes: %{
              id: "card-untitled",
              entry: entry(name: nil, date: "1922-09-04", poster: true)
            }
          }
        ]
      }
    ]
  end

  # --- Fixtures ----------------------------------------------------------

  # `image_url/2` reads `entity.images` (list of `%{role:, content_url:}`).
  # `content_url` is bogus on purpose — the real `<img>` will 404 in the
  # storybook chrome, but the layout machinery still renders correctly.
  # Variations that need to verify "no artwork" path pass `poster: false`.

  defp entry(opts) do
    type = Keyword.get(opts, :type, :movie)
    name = Keyword.get(opts, :name, "Sample Show")
    date = Keyword.get(opts, :date, "1922-09-04")
    poster? = Keyword.get(opts, :poster, true)
    progress = Keyword.get(opts, :progress)

    images =
      if poster?,
        do: [%{role: "poster", content_url: "fixtures/poster.jpg"}],
        else: []

    %{
      entity: %{
        id: "entity-" <> Atom.to_string(type) <> "-" <> Integer.to_string(:erlang.phash2(name)),
        name: name,
        type: type,
        date_published: date,
        images: images
      },
      progress: progress
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

  defp name_for_type(:movie), do: "Sample Movie"
  defp name_for_type(:tv_series), do: "Sample TV Show"
  defp name_for_type(:movie_series), do: "Sample Movie Series"
  defp name_for_type(:video_object), do: "Sample Video"
end
