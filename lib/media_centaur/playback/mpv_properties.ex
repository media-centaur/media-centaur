defmodule MediaCentaur.Playback.MpvProperties do
  @moduledoc """
  What mpv last reported: the observed properties' current values, as one
  value the session folds every `property-change` into (`apply/3`) and
  every reader of the viewing reads from (`Playback.Viewing`).

  `observed/0` is the list the session asks mpv to observe at attach.
  Two of them are reacted to without being kept: `path` (the advance
  signal, compared against the entry) and `eof-reached` (the end). The
  parse of mpv's `track-list` into `TrackResolver.Track` structs lives
  here (`parse_track_list/1`): languages are canonicalised to ISO 639-2/T
  at this boundary, so nothing downstream reconciles mpv's "en"/"jpn"
  against TMDB's "en"/"ja".

  A value mpv reports in a shape the mirror does not expect (a
  `time-pos` of nil between files, a `track-list` that is not a list) is
  left as it was.
  """

  alias MediaCentaur.Iso639
  alias MediaCentaur.Playback.TrackResolver.Track

  defstruct position: 0.0,
            duration: 0.0,
            paused: false,
            # mpv `chapter-list` for the loaded file (`[%{"title", "time"}]`),
            # used by `Completion` to complete at the credits boundary. Empty
            # for files without chapters.
            chapters: [],
            # mpv's current `chapter` index; nil between files or with none.
            chapter: nil,
            audio_tracks: [],
            subtitle_tracks: [],
            # Raw mpv-reported selected track ids (not derived languages).
            # The comparison languages are resolved from these against the
            # *complete* track list at capture time — see
            # `LanguageContext.current_selection/4` — so an early `sid` event
            # that lands before subtitle tracks demux can't freeze a stale
            # "no subs" baseline.
            aid: nil,
            sid: nil,
            # mpv's playlist shape. The queue check (`MpvSession`) appends a
            # successor only while `playlist_count - playlist_pos == 1`.
            playlist_count: 1,
            playlist_pos: 0,
            # The current `sub-text` line; nil with no track or between lines.
            subtitle_text: nil

  @type t :: %__MODULE__{
          position: number(),
          duration: number(),
          paused: boolean(),
          chapters: [map()],
          chapter: integer() | nil,
          audio_tracks: [Track.t()],
          subtitle_tracks: [Track.t()],
          aid: term(),
          sid: term(),
          playlist_count: integer(),
          playlist_pos: integer(),
          subtitle_text: String.t() | nil
        }

  @observed ~w(time-pos duration pause eof-reached track-list aid sid chapter-list playlist-count playlist-pos path sub-text chapter)

  @doc "The mpv property names the session observes, in the order it registers them."
  @spec observed() :: [String.t()]
  def observed, do: @observed

  @doc "The mirror with one `property-change` folded in; unchanged for a value in an unexpected shape."
  @spec apply(t(), String.t(), term()) :: t()
  def apply(%__MODULE__{} = mirror, "time-pos", position) when is_number(position),
    do: %{mirror | position: position}

  def apply(%__MODULE__{} = mirror, "duration", duration) when is_number(duration),
    do: %{mirror | duration: duration}

  def apply(%__MODULE__{} = mirror, "pause", paused) when is_boolean(paused),
    do: %{mirror | paused: paused}

  def apply(%__MODULE__{} = mirror, "chapter-list", chapters) when is_list(chapters),
    do: %{mirror | chapters: chapters}

  def apply(%__MODULE__{} = mirror, "chapter", index),
    do: %{mirror | chapter: if(is_integer(index), do: index)}

  def apply(%__MODULE__{} = mirror, "track-list", tracks) when is_list(tracks) do
    {audio_tracks, subtitle_tracks} = parse_track_list(tracks)
    %{mirror | audio_tracks: audio_tracks, subtitle_tracks: subtitle_tracks}
  end

  def apply(%__MODULE__{} = mirror, "aid", aid), do: %{mirror | aid: aid}
  def apply(%__MODULE__{} = mirror, "sid", sid), do: %{mirror | sid: sid}

  def apply(%__MODULE__{} = mirror, "playlist-count", count) when is_integer(count),
    do: %{mirror | playlist_count: count}

  def apply(%__MODULE__{} = mirror, "playlist-pos", pos) when is_integer(pos),
    do: %{mirror | playlist_pos: pos}

  def apply(%__MODULE__{} = mirror, "sub-text", text) when is_binary(text) and text != "",
    do: %{mirror | subtitle_text: text}

  def apply(%__MODULE__{} = mirror, "sub-text", _absent), do: %{mirror | subtitle_text: nil}
  def apply(%__MODULE__{} = mirror, _name, _data), do: mirror

  @doc """
  The mirror for the next file of a playlist: everything the file owns
  cleared. `aid`/`sid` stay — mpv keeps a selected track id across the
  files of a playlist and reports an observed property only when it
  changes, so the next file brings no `sid` event while `sid` holds;
  clearing them here read "no subtitles" and captured a subtitles-off
  override for the series on every advance. The playlist shape stays: it
  is mpv's, not the file's.
  """
  @spec reset_for_file(t()) :: t()
  def reset_for_file(%__MODULE__{} = mirror) do
    %{
      mirror
      | position: 0.0,
        duration: 0.0,
        chapters: [],
        chapter: nil,
        subtitle_text: nil,
        audio_tracks: [],
        subtitle_tracks: []
    }
  end

  @doc """
  Parse mpv's `track-list` property value (a list of mpv track maps)
  into `{audio_tracks, subtitle_tracks}` of `TrackResolver.Track` structs.
  """
  @spec parse_track_list([map()]) :: {[Track.t()], [Track.t()]}
  def parse_track_list(tracks) when is_list(tracks) do
    {audio_raw, sub_raw} =
      Enum.split_with(tracks, fn track -> Map.get(track, "type") == "audio" end)

    sub_raw = Enum.filter(sub_raw, fn track -> Map.get(track, "type") == "sub" end)

    {Enum.map(audio_raw, &build_track/1), Enum.map(sub_raw, &build_track/1)}
  end

  def parse_track_list(_), do: {[], []}

  defp build_track(track) do
    %Track{
      index: Map.get(track, "id"),
      # Boundary normalization: every track language entering the system
      # is canonicalized to 3-letter ISO 639-2/T here, so downstream code
      # never has to reconcile mpv's "en"/"jpn" forms against TMDB's
      # "en"/"ja" forms — they're all the same form past this point.
      lang: Iso639.normalize(lang_of(track)),
      title: Map.get(track, "title"),
      forced: Map.get(track, "forced", false) == true,
      # The `default` disposition pairs with `forced` to expose the
      # mislabel signature the resolver distrusts (`forced+default` on a
      # full dialogue track). mpv exposes a boolean `default` per track.
      default: Map.get(track, "default", false) == true,
      sdh: sdh_of(track),
      # The codec tells a bitmap subtitle track (PGS, VobSub) from text;
      # a player that draws nothing cannot show the former (`Viewing`).
      codec: Map.get(track, "codec")
    }
  end

  defp lang_of(track) do
    case Map.get(track, "lang") do
      lang when is_binary(lang) and lang != "" -> lang
      _ -> nil
    end
  end

  # mpv exposes a "hearing-impaired" flag in track-list when the
  # source codec/container tags it (Matroska's flag-hearing-impaired,
  # MP4's `name` element with conventional SDH markers). When absent,
  # fall back to a title-text heuristic — encoders frequently set the
  # title to "SDH" or "CC" by convention.
  defp sdh_of(track) do
    case Map.get(track, "hearing-impaired") do
      true ->
        true

      _ ->
        case Map.get(track, "title") do
          title when is_binary(title) ->
            String.contains?(String.downcase(title), ["sdh", "cc", "hearing impaired"])

          _ ->
            false
        end
    end
  end
end
