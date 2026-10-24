defmodule MediaCentaurWeb.Storybook.ViewingLayer.ViewingLayer do
  @moduledoc """
  The viewing layer, a remote player's OSD drawn by the page over the
  device's native video (`campaigns/remote-players.md`, M5; mockup
  direction 3). Each variation is one of the layer's states at the TV
  page's real size, 960×540; the frame's gradient stands in for the video.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Playback.TrackResolver.Track
  alias MediaCentaur.Playback.Viewing

  def function, do: &MediaCentaurWeb.Components.ViewingLayer.viewing_layer/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="viewing-story">
      <.psb-variation/>
    </div>
    """
  end

  @chapters [
    %{"title" => "Intro", "time" => 0.0},
    %{"title" => "Story", "time" => 92.5},
    %{"title" => "End Credits", "time" => 4520.0}
  ]

  @audio [
    %Track{index: 1, lang: "eng", codec: "dts"},
    %Track{index: 2, lang: "deu", codec: "ac3"},
    %Track{index: 3, lang: "eng", title: "Commentary", codec: "aac"}
  ]

  @subtitles [
    %Track{index: 1, lang: "eng", codec: "subrip"},
    %Track{index: 2, lang: "eng", title: "English (forced)", forced: true, codec: "subrip"},
    %Track{index: 3, lang: "eng", codec: "hdmv_pgs_subtitle"}
  ]

  defp viewing(overrides) do
    struct!(
      %Viewing{
        player: "player",
        entity_id: "entity",
        profile_id: "profile",
        entity_name: "Sample Show",
        season_number: 2,
        episode_number: 4,
        episode_name: "The Long Night",
        content_url: "/shows/a.mkv",
        position_seconds: 1872.0,
        duration_seconds: 4960.0,
        state: :playing,
        chapters: @chapters,
        chapter: 1,
        audio_tracks: @audio,
        subtitle_tracks: @subtitles,
        aid: 1,
        sid: 1
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :playing,
        description:
          "Playing — the bar shows for a few seconds after a key: scrim, title, seek bar with chapter ticks",
        attributes: %{viewing: viewing([]), bar_shown?: true}
      },
      %Variation{
        id: :paused,
        description: "Paused — the bar stays, the fill turns amber, a pause glyph in the centre",
        attributes: %{viewing: viewing(state: :paused), bar_shown?: true}
      },
      %Variation{
        id: :skip_intro,
        description: "Skip Intro at the top right while the intro chapter plays; the bar hidden",
        attributes: %{viewing: viewing(chapter: 0, position_seconds: 12.0, prompt: {:skip_intro, 92.5})}
      },
      %Variation{
        id: :next_episode,
        description: "Next Episode during the credits with a successor queued",
        attributes: %{
          viewing:
            viewing(chapter: 2, position_seconds: 4530.0, successor_queued?: true, prompt: :next_episode)
        }
      },
      %Variation{
        id: :countdown,
        description: "The countdown in the last 20 s",
        attributes: %{
          viewing:
            viewing(
              chapter: 2,
              position_seconds: 4948.0,
              successor_queued?: true,
              prompt: {:next_episode_in, 12}
            )
        }
      },
      %Variation{
        id: :past_the_end,
        description:
          "mpv's position a little past the duration at the end of a file: the fill full, the bar intact",
        attributes: %{viewing: viewing(position_seconds: 4960.4), bar_shown?: true}
      },
      %Variation{
        id: :subtitle,
        description: "A subtitle line, bar hidden — the usual state while watching",
        attributes: %{
          viewing:
            viewing(subtitle_text: "I never said it would be easy.\nOnly that it would be worth it.")
        }
      },
      %Variation{
        id: :subtitle_with_bar,
        description: "The subtitle line lifts above the bar while the bar shows",
        attributes: %{viewing: viewing(subtitle_text: "A line while the bar is up."), bar_shown?: true}
      },
      %Variation{
        id: :track_menu,
        description:
          "The track menu on MENU: Audio and Subtitles; a bitmap (PGS) track cannot be chosen",
        attributes: %{viewing: viewing([]), menu_open?: true}
      },
      %Variation{
        id: :track_menu_bitmap_only,
        description: "A file whose only subtitles are bitmap says so under the columns",
        attributes: %{
          viewing:
            viewing(
              sid: false,
              subtitle_tracks: [
                %Track{index: 1, lang: "eng", codec: "hdmv_pgs_subtitle"},
                %Track{index: 2, lang: "fra", codec: "hdmv_pgs_subtitle"}
              ]
            ),
          menu_open?: true
        }
      }
    ]
  end
end
