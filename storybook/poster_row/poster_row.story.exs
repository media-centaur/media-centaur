defmodule MediaCentaurWeb.Storybook.PosterRow.PosterRow do
  @moduledoc """
  Horizontal 8-up poster row — used on Home for "Recently Added".

  ## Contract shape (typed)

  The component takes `attr :id` (the row's DOM id — a page may hold
  several rows) and `attr :items, :list, required: true` of
  `MediaCentaurWeb.Components.PosterRow.Item.t()` structs:

      %Item{
        id: term(),
        entity_id: String.t() | nil,   # a library entity, opened by `select_entity`
        ref: {tmdb_id, :movie | :tv_series} | nil,   # a TMDB identity, opened by `open_title`
        name: String.t(),
        year: String.t() | nil,
        poster_url: String.t() | nil,
        marker: String.t() | nil        # the quiet state chip: In library, Tracking, Auto-grab
      }

  Variations construct literal `%Item{}` structs — the contract is
  typed and the story demonstrates that.

  ## Variation matrix

    * Items axis — full row (8), single item, empty list (renders nothing).
    * Subject axis — library entities (Home), TMDB identities (Discovery).
    * Marker axis — a tile with and without its state chip.
    * Chip and glyphs axis — a date chip at the head, the social glyphs' pill.
    * Artwork axis — all-with-posters, all-fallback, mixed.
    * Edge cases — long name (truncate), no year, TV-style year, numeric year.
    * See-all axis — trailing "See all" card when `see_all_href` is set.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.Components.PosterRow.Item

  def function, do: &MediaCentaurWeb.Components.PosterRow.poster_row/1
  def render_source, do: :function

  # Row uses horizontal scroll on overflow; the default two-column preview
  # is too narrow to show 8 cards side-by-side, so go full-bleed.
  def layout, do: :one_column

  # The Phoenix Storybook sandbox wraps each preview in a `flex flex-col
  # items-center` container, which shrinks block children to their
  # intrinsic content size. `.row-scroll` defines its children's widths
  # with `flex: 0 0 calc(100% / var(--cols) ...)` — without an explicit
  # full-width wrapper that math resolves against `width: 0` and the
  # cards collapse. The wrapper restores the production width context.
  def template do
    """
    <div class="w-full" psb-code-hidden>
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :full_row,
        description:
          "Standard `Recently Added` row — 8 items, all with posters. " <>
            "Demonstrates the 8-up horizontal layout. The placeholder image URL " <>
            "404s in storybook chrome but the layout still resolves correctly.",
        attributes: %{
          id: "story-full-row",
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
        id: :with_see_all,
        description:
          "`see_all_href` set — a trailing \"See all\" card renders as the last " <>
            "slot in the scrollable row, matching the Continue Watching row. " <>
            "Navigates to the linked library view.",
        attributes: %{
          id: "story-see-all-row",
          see_all_href: "/library",
          items:
            for i <- 1..6 do
              %Item{
                id: "sa-#{i}",
                entity_id: "entity-sa-#{i}",
                name: "Sample Show #{i}",
                year: Integer.to_string(1920 + rem(i, 6)),
                poster_url: poster_placeholder(i)
              }
            end
        }
      },
      %Variation{
        id: :offline_item,
        description:
          "`available?: false` — the entry's storage is offline: the projection " <>
            "withheld the poster URL, so the card shows a neutral block, the " <>
            "name and year, and no Play overlay.",
        attributes: %{
          id: "story-offline-row",
          items: [
            %Item{
              id: "offline",
              entity_id: "entity-offline",
              name: "Offline Sample",
              year: "1923",
              poster_url: nil,
              available?: false
            },
            %Item{
              id: "online",
              entity_id: "entity-online",
              name: "Online Sample",
              year: "1924",
              poster_url: poster_placeholder(2)
            }
          ]
        }
      },
      %Variation{
        id: :single_item,
        description:
          "One item — verifies the row renders cleanly with a single card and " <>
            "the scroll layout doesn't collapse.",
        attributes: %{
          id: "story-single-row",
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
        attributes: %{id: "story-empty-row", items: []}
      },
      %Variation{
        id: :chips_and_glyphs,
        description:
          "The two other things a Discovery tile can carry: `chip`, a date at the " <>
            "poster's head (an opening date on In Theaters, a release month on " <>
            "Coming Up), and `glyphs`, the title's social glyphs at their grade in " <>
            "a dark pill at the top right (Reviewed by Friends) — with and without " <>
            "the marker.",
        attributes: %{
          id: "story-chips-row",
          show_play_button: false,
          items: [
            %Item{
              id: "chip-1",
              ref: {201, :movie},
              name: "Movie A",
              year: "2026",
              poster_url: poster_placeholder(1),
              chip: "Oct 24",
              marker: "Tracking"
            },
            %Item{
              id: "chip-2",
              ref: {202, :movie},
              name: "Movie B",
              year: "2027",
              poster_url: poster_placeholder(2),
              chip: "Dec"
            },
            %Item{
              id: "glyph-1",
              ref: {203, :movie},
              name: "Movie C",
              year: "2026",
              poster_url: poster_placeholder(3),
              glyphs: %{flags: [:love], grades: %{love: :plain}, tips: %{love: "A friend loved it"}}
            },
            %Item{
              id: "glyph-2",
              ref: {204, :movie},
              name: "Movie D",
              year: "2026",
              poster_url: poster_placeholder(4),
              marker: "In library",
              glyphs: %{
                flags: [:like, :dislike, :review],
                grades: %{like: :gold, dislike: :plain, review: :silver},
                tips: %{}
              }
            }
          ]
        }
      },
      %Variation{
        id: :tmdb_identities,
        description:
          "Tiles keyed by `ref`, a TMDB identity, as Discovery's shelves draw them: " <>
            "the tile opens the title detail (`open_title`) and carries no Play; " <>
            "`marker` is the quiet state chip at the poster's foot — In library, " <>
            "Tracking, Auto-grab — and absent for a title the app has no stance on.",
        attributes: %{
          id: "story-tmdb-row",
          show_play_button: false,
          items: [
            %Item{
              id: "ref-1",
              ref: {101, :movie},
              name: "Movie A",
              year: "2026",
              poster_url: poster_placeholder(1),
              marker: "In library"
            },
            %Item{
              id: "ref-2",
              ref: {102, :movie},
              name: "Movie B",
              year: "2026",
              poster_url: poster_placeholder(2),
              marker: "Tracking"
            },
            %Item{
              id: "ref-3",
              ref: {103, :tv_series},
              name: "Sample Show",
              year: "2026",
              poster_url: poster_placeholder(3),
              marker: "Auto-grab"
            },
            %Item{
              id: "ref-4",
              ref: {104, :movie},
              name: "Movie D",
              year: "2026",
              poster_url: poster_placeholder(4)
            },
            %Item{
              id: "ref-5",
              ref: {105, :movie},
              name: "Movie Without Artwork",
              year: "2026",
              poster_url: nil,
              marker: "In library"
            }
          ]
        }
      },
      %Variation{
        id: :play_button_disabled,
        description:
          "`show_play_button: false` — the hover play overlay (UIDR-027, " <>
            "Settings entry `card_play_button`) is suppressed; hovering the " <>
            "card shows nothing. The default (`true`) reveals a play button " <>
            "on hover in every other variation.",
        attributes: %{
          id: "story-no-play-row",
          show_play_button: false,
          items: [
            %Item{
              id: "no-play",
              entity_id: "entity-no-play",
              name: "Sample Without Play",
              year: "1924",
              poster_url: poster_placeholder(1)
            }
          ]
        }
      },
      %Variation{
        id: :no_poster_fallback,
        description:
          "All items have `poster_url: nil` — every card renders the fallback " <>
            "name + year overlay instead of an `<img>`. Verifies the fallback path.",
        attributes: %{
          id: "story-fallback-row",
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
          id: "story-mixed-row",
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
      %Variation{
        id: :fallback_edge_cases,
        description:
          "Fallback-overlay edge cases rendered side-by-side in a single row " <>
            "(all `poster_url: nil`). Left to right: very long name (truncate), " <>
            "no year (year sub-line suppressed), TV-style year string, plain " <>
            "numeric year. Production rows are always dense, so testing edge " <>
            "cases as siblings — rather than as one-item rows — matches the " <>
            "real card width and lets the truncate / suppression behaviour be " <>
            "compared at a glance.",
        attributes: %{
          id: "story-edge-row",
          items: [
            %Item{
              id: "long",
              entity_id: "entity-long",
              name: "An Extraordinarily Long Sample Title That Definitely Exceeds The Card Width",
              year: "1923",
              poster_url: nil
            },
            %Item{
              id: "no-year",
              entity_id: "entity-no-year",
              name: "Sample Without Year",
              year: nil,
              poster_url: nil
            },
            %Item{
              id: "tv-year",
              entity_id: "entity-tv-year",
              name: "Sample TV Show",
              year: "S2 · 2026",
              poster_url: nil
            },
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
