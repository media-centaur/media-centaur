defmodule MediaCentarr.Playback.LanguageContext do
  @moduledoc """
  Glue between `MpvSession` and the language-preferences subsystem.
  Owns all the impure work (DB lookups for policy/override/entity
  metadata) and the parsing of mpv's `track-list` property into
  `TrackResolver.Track` structs.

  `MpvSession` calls `init/1` at session start to load the language
  context once, and `parse_track_list/1` whenever mpv emits a
  track-list update.
  """

  alias MediaCentarr.Library
  alias MediaCentarr.Library.{Movie, TVSeries}
  alias MediaCentarr.Playback.LanguagePolicy
  alias MediaCentarr.Playback.TrackResolver
  alias MediaCentarr.Playback.TrackResolver.Track
  alias MediaCentarr.Repo

  @type t :: %{
          policy: LanguagePolicy.t(),
          override: Library.MediaTrackOverride.t() | nil,
          owner_type: :tv_series | :movie | nil,
          owner_id: String.t() | nil,
          original_language: String.t() | nil,
          priority_args: TrackResolver.priority_args()
        }

  @doc """
  Build the language context for a playback session. Returns a context
  map even when the entity type is unsupported (extras, video_objects)
  — in that case `owner_type` is `nil` and the override flow is skipped,
  but the global policy still applies via `priority_args`.
  """
  @spec init(%{
          required(:entity_id) => String.t() | nil,
          optional(:movie_id) => String.t() | nil,
          optional(:episode_id) => String.t() | nil,
          optional(:video_object_id) => String.t() | nil,
          optional(:extra_id) => String.t() | nil
        }) :: t()
  def init(params) do
    {owner_type, owner_id, original_language} = resolve_owner(params)

    policy = LanguagePolicy.load()
    override = if owner_type, do: Library.get_media_track_override(owner_type, owner_id)
    priority_args = TrackResolver.priority_args(policy, override, original_language)

    %{
      policy: policy,
      override: override,
      owner_type: owner_type,
      owner_id: owner_id,
      original_language: original_language,
      priority_args: priority_args
    }
  end

  @doc """
  Convert `priority_args` into mpv launch flags. Returns an ordered
  list of `--...=` strings suitable for splicing into mpv's argv.
  Empty lists for `alang`/`slang` are omitted entirely (mpv treats
  the flag's absence as "no preference").
  """
  @spec to_mpv_flags(TrackResolver.priority_args()) :: [String.t()]
  def to_mpv_flags(args) do
    []
    |> append_lang_flag("--alang", args.alang)
    |> append_lang_flag("--slang", args.slang)
    |> Kernel.++([
      if(args.sub_visibility, do: "--sub-visibility=yes", else: "--sub-visibility=no"),
      "--subs-with-matching-audio=#{args.subs_match_audio}"
    ])
    |> Kernel.++(if(args.disable_subs, do: ["--sid=no"], else: []))
  end

  defp append_lang_flag(acc, _flag, []), do: acc
  defp append_lang_flag(acc, flag, langs), do: acc ++ ["#{flag}=#{Enum.join(langs, ",")}"]

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
      lang: lang_of(track),
      title: Map.get(track, "title"),
      forced: Map.get(track, "forced", false) == true,
      sdh: sdh_of(track)
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

  @doc """
  Look up a track's language by its mpv id within an audio or subtitle
  track list.
  """
  @spec lang_at(non_neg_integer() | nil, [Track.t()]) :: String.t() | nil
  def lang_at(nil, _tracks), do: nil

  def lang_at(index, tracks) do
    case Enum.find(tracks, fn track -> track.index == index end) do
      nil -> nil
      track -> track.lang
    end
  end

  @doc """
  Look up a sub track's forced flag by its mpv id.
  """
  @spec forced_at(non_neg_integer() | nil, [Track.t()]) :: boolean()
  def forced_at(nil, _tracks), do: false

  def forced_at(index, tracks) do
    case Enum.find(tracks, fn track -> track.index == index end) do
      nil -> false
      track -> track.forced
    end
  end

  # ---------------------------------------------------------------------------
  # Owner / metadata resolution
  # ---------------------------------------------------------------------------

  defp resolve_owner(%{extra_id: extra_id}) when is_binary(extra_id), do: {nil, nil, nil}

  defp resolve_owner(%{movie_id: movie_id}) when is_binary(movie_id) do
    case Repo.get(Movie, movie_id) do
      nil -> {nil, nil, nil}
      movie -> {:movie, movie.id, movie.original_language}
    end
  end

  defp resolve_owner(%{episode_id: episode_id, entity_id: entity_id})
       when is_binary(episode_id) and is_binary(entity_id) do
    # Episode's owner is the TV series root (entity_id). We don't need to
    # walk Episode → Season → TVSeries — entity_id is already the series.
    case Repo.get(TVSeries, entity_id) do
      nil -> {nil, nil, nil}
      series -> {:tv_series, series.id, series.original_language}
    end
  end

  defp resolve_owner(_), do: {nil, nil, nil}
end
