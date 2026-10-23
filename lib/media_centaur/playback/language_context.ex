defmodule MediaCentaur.Playback.LanguageContext do
  @moduledoc """
  The track policy of one playback session: the language preferences
  loaded for its entry (`init/2`), the resolver's choice on each
  `track-list` and the subtitle enforcement it implies (`on_track_list/3`),
  and the capture of a viewer's own track switch as an override
  (`capture/3`). Owns the impure work — the DB reads for policy, override
  and entity metadata, the override write — and answers `MpvSession` with
  the IPC to send; the session keeps the capture timer and sends. mpv's
  `track-list` is parsed into `TrackResolver.Track` structs by
  `MpvProperties`.

  The resolver is the source of truth: once subtitle tracks exist, mpv's
  `sid` is made to match its pick. Enforcement is driven from `track-list`
  updates only — a *viewer's* track switch fires `aid`/`sid`, never
  `track-list`, so it is never clobbered, and the session's own
  `set_property sid` echo lands on the capture path, not here — no loop.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.{Format, Iso639, Library}
  alias MediaCentaur.Playback.{Entry, Events, LanguagePolicy, MpvProperties, OverrideCapture}
  alias MediaCentaur.Playback.{TrackResolver, Viewing}
  alias MediaCentaur.Playback.TrackResolver.Track

  defstruct [
    :policy,
    :override,
    :owner_type,
    :owner_id,
    :original_language,
    :priority_args,
    # The lang-based slice of the last resolution (lang/forced, not indices
    # — survives re-rips), the baseline a capture compares against. nil
    # until the first resolution.
    resolver_choice: nil,
    # The last `sid` pushed to mpv by enforcement, so `set_property sid` is
    # sent only when the resolved target changes (no IPC spam, no loop).
    enforced_sid: nil
  ]

  @type t :: %__MODULE__{
          policy: LanguagePolicy.t(),
          override: Library.MediaTrackOverride.t() | nil,
          owner_type: :tv_series | :movie | nil,
          owner_id: String.t() | nil,
          original_language: String.t() | nil,
          priority_args: TrackResolver.priority_args(),
          resolver_choice: OverrideCapture.state() | nil,
          enforced_sid: term()
        }

  @doc """
  Build the language context for a playback session of `entry`. Returns a
  context map even when the entry's playable is unsupported (extras,
  video objects, an unattributed file) — in that case `owner_type` is
  `nil` and the override flow is skipped, but the global policy still
  applies via `priority_args`. The override read is the session's
  profile's own (`profile_id`, ADR-078).
  """
  @spec init(String.t(), Entry.t()) :: t()
  def init(profile_id, %Entry{} = entry) do
    {owner_type, owner_id, original_language} = resolve_owner(entry)

    policy = LanguagePolicy.load()

    override =
      if owner_type, do: Library.MediaTrackOverrides.get(profile_id, owner_type, owner_id)

    priority_args = TrackResolver.priority_args(policy, override, original_language)

    %__MODULE__{
      policy: policy,
      override: override,
      owner_type: owner_type,
      owner_id: owner_id,
      original_language: original_language,
      priority_args: priority_args
    }
  end

  @doc """
  The policy after a `track-list` update, with the IPC commands to send.

  The choice is recomputed on *every* update, not just the first: mpv
  populates tracks incrementally — audio frequently demuxes before
  subtitles — so the first non-empty list can be audio-only, which would
  otherwise freeze a wrong "no subs" baseline. Enforcement is gated on
  subtitle tracks being present, so subtitles never flash off during that
  window, and idempotent: a `set_property sid` goes out only when the
  resolved target changes. A player that draws no subtitles
  (`draws_subtitles?` false) never has a bitmap track picked; a file whose
  subtitle tracks it cannot draw at all gets them off, or mpv's own
  `slang` would pick a bitmap track nothing renders.
  """
  @spec on_track_list(t(), MpvProperties.t(), boolean()) :: {t(), [list()]}
  def on_track_list(%__MODULE__{} = context, %MpvProperties{} = properties, draws_subtitles?) do
    %MpvProperties{audio_tracks: audio_tracks, subtitle_tracks: subtitle_tracks} = properties

    if audio_tracks == [] and subtitle_tracks == [] do
      {context, []}
    else
      drawable =
        if draws_subtitles?,
          do: subtitle_tracks,
          else: Enum.reject(subtitle_tracks, &Viewing.bitmap_track?/1)

      result =
        TrackResolver.resolve(
          context.policy,
          context.override,
          audio_tracks,
          drawable,
          context.original_language
        )

      choice = %{audio_lang: result.audio_lang, sub_lang: result.sub_lang, sub_forced: result.sub_forced}

      if choice != context.resolver_choice do
        Log.info(:playback, "track-resolver: " <> Enum.join(result.decision_log, " | "))
      end

      enforce_subtitle_selection(%{context | resolver_choice: choice}, result, drawable, subtitle_tracks)
    end
  end

  defp enforce_subtitle_selection(context, result, drawable, all_subtitle_tracks) do
    case sid_target(result, drawable, all_subtitle_tracks) do
      :skip ->
        {context, []}

      {:set, sid} when sid == context.enforced_sid ->
        {context, []}

      {:set, sid} ->
        Log.info(:playback, "track-resolver: enforcing sid=#{inspect(sid)}")
        {%{context | enforced_sid: sid}, [["set_property", "sid", sid]]}
    end
  end

  defp sid_target(_result, [], [_ | _]), do: {:set, "no"}
  defp sid_target(result, drawable, _all), do: TrackResolver.sid_enforcement(result, drawable)

  @doc """
  Whether a viewer's track switch is worth capturing: the entry has an
  override owner (a movie or a series — not an extra or a video object)
  and the resolver has chosen, so there is a baseline to compare against.
  """
  @spec captures?(t()) :: boolean()
  def captures?(%__MODULE__{owner_type: owner_type, resolver_choice: choice}),
    do: not is_nil(owner_type) and not is_nil(choice)

  @doc """
  Captures the viewer's settled track selection as the profile's override
  for the entry's owner, when it differs from the resolver's choice.

  The selection is derived now, from the complete track lists — not from
  a snapshot taken when the `aid`/`sid` event fired: mpv auto-selects a
  sub from `slang` before subtitle tracks demux, so an event-time snapshot
  can read "no subs" while the eng sub is in fact selected. Deriving here
  is what stops the per-series `subtitles_off` poison — see
  `current_selection/4`.
  """
  @spec capture(t(), String.t(), MpvProperties.t()) :: :ok
  def capture(%__MODULE__{} = context, profile_id, %MpvProperties{} = properties) do
    %MpvProperties{aid: aid, sid: sid, audio_tracks: audio_tracks, subtitle_tracks: subtitle_tracks} =
      properties

    selection = current_selection(aid, sid, audio_tracks, subtitle_tracks)

    case OverrideCapture.compute(context.resolver_choice, selection) do
      :no_change -> :ok
      {:override, attrs} -> persist_override(context, profile_id, attrs)
    end
  end

  defp persist_override(%__MODULE__{owner_type: owner_type, owner_id: owner_id}, profile_id, attrs) do
    case Library.MediaTrackOverrides.upsert(profile_id, owner_type, owner_id, attrs) do
      {:ok, _override} ->
        Log.info(
          :playback,
          "captured track override (#{owner_type}=#{Format.short_id(owner_id)}) — #{inspect(attrs)}"
        )

        Events.broadcast(%Events.TrackOverrideChanged{
          profile_id: profile_id,
          owner_type: owner_type,
          owner_id: owner_id
        })

      {:error, changeset} ->
        Log.warning(:playback, "failed to persist track override — #{inspect(changeset.errors)}")
    end

    :ok
  end

  @doc "The policy for the next file of a playlist: the choice and the enforcement start over."
  @spec reset_for_file(t()) :: t()
  def reset_for_file(%__MODULE__{} = context), do: %{context | resolver_choice: nil, enforced_sid: nil}

  @doc """
  Convert `priority_args` into mpv options, as `{option, value}` pairs
  (`Playback.LaunchFlags.option/0`): `alang`, `slang`,
  `subs-with-matching-audio`, and `sid=no` when subtitles are disabled.
  Empty lists for `alang`/`slang` are omitted entirely (mpv treats the
  option's absence as "no preference").
  """
  @spec to_mpv_options(TrackResolver.priority_args()) :: [{String.t(), String.t()}]
  def to_mpv_options(args) do
    []
    |> append_lang_option("alang", args.alang)
    |> append_lang_option("slang", args.slang)
    |> Kernel.++([{"subs-with-matching-audio", to_string(args.subs_match_audio)}])
    |> Kernel.++(if(args.disable_subs, do: [{"sid", "no"}], else: []))
  end

  defp append_lang_option(acc, _name, []), do: acc
  defp append_lang_option(acc, name, langs), do: acc ++ [{name, Enum.join(langs, ",")}]

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

  @doc """
  Derive the override-capture comparison state (audio/subtitle language and
  forced flag) from mpv's currently-selected track indices and the current
  track lists.

  Must be called with the **complete** track lists, not a snapshot from when
  the `aid`/`sid` event fired: mpv emits an early `sid` event (its own
  `--slang` auto-selection) before subtitle tracks finish demuxing, so
  resolving the same index against an empty list yields `nil` and against the
  complete list yields the real language. Capturing the stale `nil` is what
  poisoned per-series overrides into `subtitles_off: true`. Storing the raw
  indices and resolving here at capture time — once `track-list` has fully
  populated — closes that race.

  `sub` may be `nil` or `false` (mpv's "no subtitle"); both derive `nil`.
  """
  @spec current_selection(
          non_neg_integer() | nil,
          non_neg_integer() | false | nil,
          [Track.t()],
          [Track.t()]
        ) :: %{audio_lang: String.t() | nil, sub_lang: String.t() | nil, sub_forced: boolean()}
  def current_selection(aid, sid, audio_tracks, subtitle_tracks) do
    sid = if sid != false, do: sid

    %{
      audio_lang: lang_at(aid, audio_tracks),
      sub_lang: lang_at(sid, subtitle_tracks),
      sub_forced: forced_at(sid, subtitle_tracks)
    }
  end

  # ---------------------------------------------------------------------------
  # Owner / metadata resolution
  # ---------------------------------------------------------------------------

  defp resolve_owner(%Entry{extra_id: extra_id}) when is_binary(extra_id), do: {nil, nil, nil}

  defp resolve_owner(%Entry{movie_id: movie_id}) when is_binary(movie_id) do
    case Library.Containers.fetch(:movie, movie_id) do
      {:ok, movie} -> {:movie, movie.id, Iso639.normalize(movie.original_language)}
      _ -> {nil, nil, nil}
    end
  end

  defp resolve_owner(%Entry{episode_id: episode_id, entity_id: entity_id})
       when is_binary(episode_id) and is_binary(entity_id) do
    # Episode's owner is the TV series root (entity_id). We don't need to
    # walk Episode → Season → TVSeries — entity_id is already the series.
    case Library.Containers.fetch(:tv_series, entity_id) do
      {:ok, series} -> {:tv_series, series.id, Iso639.normalize(series.original_language)}
      _ -> {nil, nil, nil}
    end
  end

  defp resolve_owner(%Entry{}), do: {nil, nil, nil}
end
