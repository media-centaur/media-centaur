defmodule MediaCentarrWeb.Storybook.PosterRow.PosterRow do
  @moduledoc """
  Horizontal 8-up poster row — used on Home for "Recently Added".

  ## Contract shape (typed)

  The component takes `attr :items, :list, required: true` of
  `MediaCentarrWeb.Components.PosterRow.Item.t()` structs:

      %Item{
        id: term(),
        entity_id: String.t(),
        name: String.t(),
        year: String.t() | nil,
        poster_url: String.t() | nil
      }

  Variations construct literal `%Item{}` structs — the contract is
  typed and the story demonstrates that.

  ## Variation matrix

    * Items axis — full row (8), single item, empty list (renders nothing).
    * Artwork axis — all-with-posters, all-fallback, mixed.
    * Edge cases — long name (truncate), no year, TV-style year, numeric year.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentarrWeb.Components.PosterRow.Item

  def function, do: &MediaCentarrWeb.Components.PosterRow.poster_row/1
  def render_source, do: :function

  # Row uses horizontal scroll on overflow; the default two-column preview
  # is too narrow to show 8 cards side-by-side, so go full-bleed.
  def layout, do: :one_column

  def variations do
    [
      %Variation{
        id: :full_row,
        description:
          "Standard `Recently Added` row — 8 items, all with posters. " <>
            "Demonstrates the 8-up horizontal layout. The placeholder image URL " <>
            "404s in storybook chrome but the layout still resolves correctly.",
        attributes: %{
          items:
            for i <- 1..8 do
              %Item{
                id: "item-#{i}",
                entity_id: "entity-#{i}",
                name: "Sample Show #{i}",
                year: Integer.to_string(1920 + rem(i, 6)),
                poster_url: poster_placeholder(i)
              }
            end
        }
      },
      %Variation{
        id: :single_item,
        description:
          "One item — verifies the row renders cleanly with a single card and " <>
            "the scroll layout doesn't collapse.",
        attributes: %{
          items: [
            %Item{
              id: "single",
              entity_id: "entity-single",
              name: "A Quiet Sample",
              year: "1924",
              poster_url: poster_placeholder(1)
            }
          ]
        }
      },
      %Variation{
        id: :empty,
        description:
          "`items: []` — the `:if={@items != []}` guard suppresses the wrapper " <>
            "entirely. Preview should be blank (no row rendered).",
        attributes: %{items: []}
      },
      %Variation{
        id: :no_poster_fallback,
        description:
          "All items have `poster_url: nil` — every card renders the fallback " <>
            "name + year overlay instead of an `<img>`. Verifies the fallback path.",
        attributes: %{
          items:
            for i <- 1..4 do
              %Item{
                id: "fb-#{i}",
                entity_id: "entity-fb-#{i}",
                name: "Sample Show #{i}",
                year: Integer.to_string(1920 + i),
                poster_url: nil
              }
            end
        }
      },
      %Variation{
        id: :mixed_artwork,
        description:
          "Six items, alternating poster vs. no-poster. Verifies that real " <>
            "images and fallback overlays render side-by-side without layout drift.",
        attributes: %{
          items:
            for i <- 1..6 do
              %Item{
                id: "mix-#{i}",
                entity_id: "entity-mix-#{i}",
                name: "Sample Show #{i}",
                year: Integer.to_string(1920 + i),
                poster_url: if(rem(i, 2) == 1, do: poster_placeholder(i))
              }
            end
        }
      },
      %VariationGroup{
        id: :edge_cases,
        description:
          "Single-item variations exercising the fallback overlay's edge cases. " <>
            "All four pass `poster_url: nil` so the overlay renders.",
        variations: [
          %Variation{
            id: :long_name,
            description:
              "Very long name — `truncate` on the fallback overlay should clip " <>
                "it on a single line without pushing the card wider.",
            attributes: %{
              items: [
                %Item{
                  id: "long",
                  entity_id: "entity-long",
                  name: "An Extraordinarily Long Sample Title That Definitely Exceeds The Card Width",
                  year: "1923",
                  poster_url: nil
                }
              ]
            }
          },
          %Variation{
            id: :no_year,
            description:
              "`year: nil` — the year sub-line `<div>` is suppressed; only the " <>
                "name renders in the fallback overlay.",
            attributes: %{
              items: [
                %Item{
                  id: "no-year",
                  entity_id: "entity-no-year",
                  name: "Sample Without Year",
                  year: nil,
                  poster_url: nil
                }
              ]
            }
          },
          %Variation{
            id: :tv_style_year,
            description:
              "TV-style year string `\"S2 · 2026\"` (per moduledoc) — the `year` " <>
                "field is opaque to the component; whatever string is passed renders.",
            attributes: %{
              items: [
                %Item{
                  id: "tv-year",
                  entity_id: "entity-tv-year",
                  name: "Sample TV Show",
                  year: "S2 · 2026",
                  poster_url: nil
                }
              ]
            }
          },
          %Variation{
            id: :numeric_year,
            description:
              "Standard movie case — `year: \"1923\"`. Mirrors the most common " <>
                "production shape.",
            attributes: %{
              items: [
                %Item{
                  id: "num-year",
                  entity_id: "entity-num-year",
                  name: "Sample Movie",
                  year: "1923",
                  poster_url: nil
                }
              ]
            }
          }
        ]
      }
    ]
  end

  # Placeholder poster URL — `placehold.co` returns a real 2:3 image so the
  # `<img>` resolves and the layout renders with actual artwork. The slight
  # color variation per index makes the 8-up row visually distinguishable.
  defp poster_placeholder(i) do
    shade = 100 + i * 10
    "https://placehold.co/200x300/#{shade_hex(shade)}/ffffff?text=#{i}"
  end

  defp shade_hex(n) do
    n
    |> min(255)
    |> Integer.to_string(16)
    |> String.pad_leading(2, "0")
    |> String.duplicate(3)
  end
end
