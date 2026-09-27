defmodule MediaCentaurWeb.Storybook.Discovery.PersonCard do
  @moduledoc """
  One person as their latest acts (UIDR-046): the identity tile, the
  name — no clock — and a strip of posters, one per title acted on,
  each under its act glyphs centred as a group in mast order (the
  opinion, the eye, the bookmark), a flag at the grade in gold. One
  component at two widths: the Feed's rail (480, a row in the rail's
  list, three acts, a press navigates to the person) and the Friends
  page (900, a card on the inset tone, five acts, a press opens the card
  in place to every act, one row each, and the foot: your name for them,
  the switch showing or hiding their picture for you (UIDR-047), the
  key, the date, Remove friend). A person with no acts is a tile and a
  name; nothing says what a person withholds.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Social.Person
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.Act
  alias MediaCentaurWeb.Components.Discovery.Act.Entry

  def function, do: &MediaCentaurWeb.Components.Discovery.PersonCard.person_card/1
  def render_source, do: :function
  def layout, do: :one_column

  @poster "/images/storybook/sample-poster.jpg"
  @rail ~s(<div class="w-[480px]"><.psb-variation/></div>)
  @page ~s(<div class="w-[900px]"><.psb-variation/></div>)

  defp act(tmdb_id, name, flags, opts \\ []) do
    media_type = Keyword.get(opts, :media_type, :movie)
    episode = Keyword.get(opts, :episode)

    %Act{
      ref: {tmdb_id, media_type},
      title: Title.new!(%{tmdb_id: tmdb_id, media_type: media_type, name: name}),
      poster_url: Keyword.get(opts, :poster_url, @poster),
      activity_id: "activity-#{tmdb_id}-#{hd(flags)}",
      acted_at: ~U[2026-09-01 12:00:00Z],
      ago: Keyword.get(opts, :ago, "2h ago"),
      episode: episode,
      flags: flags,
      gold: Keyword.get(opts, :gold, []),
      entries:
        for flag <- flags do
          %Entry{
            activity_id: "activity-#{tmdb_id}-#{flag}",
            kind: kind(flag),
            flag: flag,
            episode: if(flag == :watched, do: episode),
            acted_at: ~U[2026-09-01 12:00:00Z]
          }
        end
    }
  end

  defp kind(:watched), do: :watched
  defp kind(:listing), do: :listing
  defp kind(_opinion), do: :review

  defp friend do
    %Person{
      pubkey: "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
      name_override: "Sample Friend",
      own?: false,
      short_npub: "npub1lyy9…8z4h",
      added_on: ~D[2026-08-30]
    }
  end

  # A friend whose published picture the reader shows: the tile's avatar
  # mark. A hidden picture has no URL at all — `Social` hands the card
  # `avatar_url: nil` with `show_avatar: false` — so the hidden fixture
  # below is `friend/0` with the switch off, not this one with a URL.
  defp friend_with_avatar, do: %{friend() | avatar_url: @poster}

  defp you,
    do: %Person{pubkey: "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5", own?: true}

  defp three_acts do
    [
      act(1399, "Sample Show", [:watched],
        media_type: :tv_series,
        episode: %Episode{season_number: 2, episode_number: 5}
      ),
      act(11, "Movie A", [:love, :watched], ago: "1d ago"),
      act(12, "Movie B", [:listing], ago: "3d ago")
    ]
  end

  defp seven_acts do
    three_acts() ++
      [
        act(13, "Movie C", [:like], ago: "4d ago"),
        act(14, "Movie D", [:watched, :listing], ago: "5d ago"),
        act(15, "Movie E", [:review], ago: "1w ago"),
        act(16, "Movie F", [:dislike, :watched], ago: "2w ago")
      ]
  end

  defp gold_acts do
    [
      act(21, "Movie G", [:love], gold: [:love]),
      act(22, "Movie H", [:watched, :listing], gold: [:watched], ago: "1d ago"),
      act(23, "Movie I", [:like], ago: "2d ago")
    ]
  end

  defp one_flag_each(width) do
    for flag <- [:love, :like, :dislike, :review, :watched, :listing] do
      %Variation{
        id: flag,
        description: "#{flag}: the glyph alone, centred over the poster",
        attributes: %{person: friend(), acts: [act(31, "Movie K", [flag])], width: width}
      }
    end
  end

  def variations do
    [
      %Variation{
        id: :rail_friend,
        description: "The rail's card: three acts; the second flies love and watched as a centred pair",
        attributes: %{person: friend(), acts: three_acts(), width: :rail},
        template: @rail
      },
      %Variation{
        id: :rail_friend_avatar,
        description:
          "A friend whose picture you show: the tile carries the avatar inside a neutral ring",
        attributes: %{person: friend_with_avatar(), acts: three_acts(), width: :rail},
        template: @rail
      },
      %Variation{
        id: :rail_no_artwork,
        description: "An act whose title has no poster: the slot names it",
        attributes: %{
          person: friend(),
          acts: [act(41, "Movie L", [:watched], poster_url: nil) | tl(three_acts())],
          width: :rail
        },
        template: @rail
      },
      %Variation{
        id: :rail_you,
        description: "The reader on the rail: the filled own tile, own acts, no foot ever",
        attributes: %{
          person: you(),
          acts: [act(11, "Movie A", [:love]), act(12, "Movie B", [:listing], ago: "3d ago")],
          width: :rail
        },
        template: @rail
      },
      %Variation{
        id: :rail_quiet,
        description: "A friend with no acts: a tile and a name, nothing about sharing",
        attributes: %{person: friend(), acts: [], width: :rail},
        template: @rail
      },
      %Variation{
        id: :rail_unnamed,
        description: "A friend with no name at all: the person glyph and Unnamed, no note about it",
        attributes: %{person: %{friend() | name_override: nil}, acts: three_acts(), width: :rail},
        template: @rail
      },
      %VariationGroup{
        id: :rail_flags,
        description: "Each flag alone at 28px, centred over its poster on the rail",
        template: @rail,
        variations: one_flag_each(:rail)
      },
      %Variation{
        id: :rail_all_slots,
        description: "One act flying love, watched and listing: the three across",
        attributes: %{
          person: friend(),
          acts: [act(51, "Movie M", [:love, :watched, :listing])],
          width: :rail
        },
        template: @rail
      },
      %Variation{
        id: :rail_gold,
        description:
          "The grade: a gold heart alone; a gold eye beside a matte bookmark; a matte thumb up",
        attributes: %{person: friend(), acts: gold_acts(), width: :rail},
        template: @rail
      },
      %Variation{
        id: :page_friend,
        description: "The Friends page's card: five of seven acts, the strip at the card's left",
        attributes: %{person: friend(), acts: seven_acts(), width: :page},
        template: @page
      },
      %Variation{
        id: :page_opened,
        description:
          "The same card opened: seven acts wrapping 5+2, one row per poster, the foot with your name for them, the picture switch on over the letter mark (the common state: nothing published yet), the key, the date and Remove friend",
        attributes: %{
          person: friend(),
          acts: seven_acts(),
          width: :page,
          opened?: true
        },
        template: @page
      },
      %Variation{
        id: :page_opened_avatar,
        description:
          "The opened card of a friend whose picture you show: the tile carries the avatar, the switch is on",
        attributes: %{
          person: friend_with_avatar(),
          acts: seven_acts(),
          width: :page,
          opened?: true
        },
        template: @page
      },
      %Variation{
        id: :page_opened_avatar_hidden,
        description:
          "The opened card with the picture switch off: the tile falls back to the letter, since a hidden picture has no URL",
        attributes: %{
          person: %{friend() | show_avatar: false},
          acts: seven_acts(),
          width: :page,
          opened?: true
        },
        template: @page
      },
      %Variation{
        id: :page_you,
        description: "The reader's page card: own acts",
        attributes: %{person: you(), acts: three_acts(), width: :page},
        template: @page
      },
      %Variation{
        id: :page_you_opened,
        description: "The reader's card opened: the rows, no foot",
        attributes: %{person: you(), acts: three_acts(), width: :page, opened?: true},
        template: @page
      },
      %Variation{
        id: :page_quiet,
        description: "A friend with no acts at the page width",
        attributes: %{person: friend(), acts: [], width: :page},
        template: @page
      },
      %VariationGroup{
        id: :page_flags,
        description: "Each flag alone, centred over the page's wider poster",
        template: @page,
        variations: one_flag_each(:page)
      },
      %Variation{
        id: :page_all_slots,
        description: "One act flying all three, at the page width",
        attributes: %{
          person: friend(),
          acts: [act(51, "Movie M", [:love, :watched, :listing])],
          width: :page
        },
        template: @page
      },
      %Variation{
        id: :page_gold,
        description: "The grade at the page width",
        attributes: %{person: friend(), acts: gold_acts(), width: :page},
        template: @page
      }
    ]
  end
end
