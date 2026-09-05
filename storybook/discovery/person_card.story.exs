defmodule MediaCentaurWeb.Storybook.Discovery.PersonCard do
  @moduledoc """
  One person on the Friends tab (UIDR-031): name as the title, the
  presence line, the Recently watched strip with its "all N" tile, the
  Tracking and Recommended rows, and a friend's footer. The You card
  differs in border, subtitle and the missing footer. Expansion is the
  host's state, shown here as an attribute.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.Person
  alias MediaCentaurWeb.Components.Discovery.Person.Entry

  def function, do: &MediaCentaurWeb.Components.Discovery.PersonCard.person_card/1
  def render_source, do: :function
  def layout, do: :one_column

  defp entry(tmdb_id, name, opts \\ []) do
    media_type = Keyword.get(opts, :media_type, :movie)

    %Entry{
      activity_id: "activity-#{tmdb_id}-#{Keyword.get(opts, :kind, :watched)}",
      ref: {tmdb_id, media_type},
      title: Title.new!(%{tmdb_id: tmdb_id, media_type: media_type, name: name}),
      poster_url: Keyword.get(opts, :poster_url),
      sentiment: Keyword.get(opts, :sentiment),
      episode: Keyword.get(opts, :episode),
      acted_at: ~U[2026-09-01 12:00:00Z]
    }
  end

  defp watched_shelf do
    [
      entry(1399, "Sample Show",
        media_type: :tv_series,
        episode: %Episode{season_number: 2, episode_number: 5},
        poster_url: "/images/sample-nosferatu-poster.jpg"
      ),
      entry(11, "Movie A"),
      entry(12, "Movie B"),
      entry(13, "Movie C"),
      entry(14, "Movie D"),
      entry(15, "Movie E"),
      entry(16, "Movie F")
    ]
  end

  defp friend(overrides) do
    struct!(
      %Person{
        id: "person-f9308a01",
        name: "Sample Friend",
        own?: false,
        pubkey: "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
        short_npub: "npub1lyy9…8z4h",
        added_on: ~D[2026-08-30],
        presence: %{text: "watched S02E05 of Sample Show", ago: "2h ago", at: ~U[2026-09-01 12:00:00Z]},
        watched: watched_shelf(),
        tracking: [
          entry(21, "Movie G", kind: :tracking),
          entry(22, "Show H", kind: :tracking, media_type: :tv_series),
          entry(23, "Movie I", kind: :tracking),
          entry(24, "Movie J", kind: :tracking)
        ],
        recommended: [
          entry(31, "Movie K", kind: :recommendation, sentiment: :love),
          entry(32, "Movie L", kind: :recommendation, sentiment: :like)
        ]
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :friend,
        description:
          "A friend with every shelf: five posters and \"all 7\", three tracked titles and " <>
            "\"1 more\", two recommendations with their sentiment glyphs, the key and Remove in the footer.",
        attributes: %{person: friend(%{})}
      },
      %Variation{
        id: :friend_expanded,
        description: "The same friend after \"all N\": every shelf in full, no tiles or counts left.",
        attributes: %{person: friend(%{}), expanded?: true}
      },
      %Variation{
        id: :friend_quiet,
        description: "A friend who has shared nothing: header and footer only.",
        attributes: %{
          person: friend(%{presence: nil, watched: [], tracking: [], recommended: []})
        }
      },
      %Variation{
        id: :you,
        description: "The You card: primary-tinted border, \"How friends see you\", no footer.",
        attributes: %{
          person:
            friend(%{
              id: "person-you",
              name: "You",
              own?: true,
              pubkey: nil,
              short_npub: nil,
              added_on: nil,
              tracking: [entry(21, "Movie G", kind: :tracking)],
              recommended: [entry(31, "Movie K", kind: :recommendation, sentiment: :love)]
            })
        }
      },
      %Variation{
        id: :you_quiet,
        description: "You before anything is shared: the subtitle says where sharing starts.",
        attributes: %{
          person:
            friend(%{
              id: "person-you",
              name: "You",
              own?: true,
              pubkey: nil,
              short_npub: nil,
              added_on: nil,
              presence: nil,
              watched: [],
              tracking: [],
              recommended: []
            })
        }
      }
    ]
  end
end
