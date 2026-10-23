defmodule MediaCentaur.Playback.Viewing do
  @moduledoc """
  One viewing's state as a reader needs it: what plays, where it is, what
  it offers. Built by `MpvSession` from its own state (`from_session/1`)
  and carried on `PlaybackStateChanged.now_playing` and on the per-player
  viewing stream (`Playback.subscribe_viewing/1`), so every surface that
  says what a player shows reads one shape.

  A remote player's OSD is the host's page (`campaigns/remote-players.md`,
  M5), so the struct carries what the page draws: the title words, the
  position, the paused state, the tracks (bitmap subtitle tracks marked by
  `bitmap_track?/1`, since a player that draws nothing cannot show them),
  the current subtitle line, and the **prompt** — Skip Intro or Next
  Episode by the desktop package's rules (`prompt/1`), judged here so the
  page shows the pill and the session acts on it with one source of truth.
  """

  alias MediaCentaur.Playback.{Completion, IntroChapter, TrackResolver}

  @countdown_window_seconds 20

  # Subtitle codecs that are pictures, which a player with no renderer
  # cannot draw: Blu-ray PGS, DVD VobSub, DVB, the XSUB of old AVIs.
  @bitmap_codecs ~w(hdmv_pgs_subtitle dvd_subtitle dvb_subtitle xsub)

  @enforce_keys [:player, :entity_id, :profile_id, :content_url, :state]
  defstruct [
    :player,
    :entity_id,
    :profile_id,
    :entity_name,
    :season_number,
    :episode_number,
    :episode_name,
    :content_url,
    :state,
    :chapter,
    :aid,
    :sid,
    :subtitle_text,
    :prompt,
    position_seconds: 0.0,
    duration_seconds: 0.0,
    chapters: [],
    audio_tracks: [],
    subtitle_tracks: [],
    successor_queued?: false
  ]

  @typedoc "What the viewing offers right now: a pill the reader can activate, or nothing."
  @type prompt :: {:skip_intro, number()} | :next_episode | {:next_episode_in, non_neg_integer()} | nil

  @type t :: %__MODULE__{
          player: MediaCentaur.Playback.player(),
          entity_id: String.t(),
          profile_id: String.t(),
          entity_name: String.t() | nil,
          season_number: integer() | nil,
          episode_number: integer() | nil,
          episode_name: String.t() | nil,
          content_url: String.t(),
          position_seconds: number(),
          duration_seconds: number(),
          state: :playing | :paused,
          chapters: [map()],
          chapter: integer() | nil,
          audio_tracks: [TrackResolver.Track.t()],
          subtitle_tracks: [TrackResolver.Track.t()],
          aid: term(),
          sid: term(),
          successor_queued?: boolean(),
          subtitle_text: String.t() | nil,
          prompt: prompt()
        }

  @doc "The viewing a session's state describes, with its prompt judged."
  @spec from_session(struct()) :: t()
  def from_session(session) do
    viewing = %__MODULE__{
      player: session.player,
      entity_id: session.entity_id,
      profile_id: session.profile_id,
      entity_name: session.entity_name,
      season_number: session.season_number,
      episode_number: session.episode_number,
      episode_name: session.episode_name,
      content_url: session.content_url,
      position_seconds: session.position || 0.0,
      duration_seconds: session.duration || 0.0,
      state: if(session.paused, do: :paused, else: :playing),
      chapters: session.chapters,
      chapter: session.chapter,
      audio_tracks: session.audio_tracks,
      subtitle_tracks: session.subtitle_tracks,
      aid: session.current_aid,
      sid: session.current_sid,
      successor_queued?: not is_nil(session.pending_next),
      subtitle_text: session.subtitle_text
    }

    %{viewing | prompt: prompt(viewing)}
  end

  @doc """
  The prompt a viewing offers, the desktop package's rules
  (`next_episode.lua`, `skip_intro.lua`): the countdown in the last
  #{@countdown_window_seconds} s with a successor queued, else Next
  Episode during a credits chapter at or after the outro floor with a
  successor queued, else Skip Intro while an intro chapter plays and a
  chapter follows it. The countdown replaces the credits pill, so auto-play
  never lands unannounced.
  """
  @spec prompt(t()) :: prompt()
  def prompt(%__MODULE__{duration_seconds: duration} = viewing)
      when is_number(duration) and duration > 0 do
    remaining = duration - viewing.position_seconds

    cond do
      viewing.successor_queued? and remaining <= @countdown_window_seconds ->
        {:next_episode_in, max(ceil(remaining), 0)}

      viewing.successor_queued? and credits_chapter_playing?(viewing) ->
        :next_episode

      true ->
        skip_intro(viewing)
    end
  end

  def prompt(_viewing), do: nil

  @doc "The seconds before the end of a file in which the countdown shows."
  @spec countdown_window_seconds() :: pos_integer()
  def countdown_window_seconds, do: @countdown_window_seconds

  @doc "Whether a subtitle track is pictures rather than text."
  @spec bitmap_track?(TrackResolver.Track.t()) :: boolean()
  def bitmap_track?(%TrackResolver.Track{codec: codec}), do: codec in @bitmap_codecs

  defp credits_chapter_playing?(%{chapter: index, chapters: chapters, duration_seconds: duration})
       when is_integer(index) do
    case Enum.at(chapters, index) do
      %{} = chapter -> Completion.credits_chapter?(chapter, duration)
      nil -> false
    end
  end

  defp credits_chapter_playing?(_viewing), do: false

  defp skip_intro(viewing) do
    case IntroChapter.skip_target(viewing.chapters, viewing.chapter) do
      nil -> nil
      target -> {:skip_intro, target}
    end
  end
end
