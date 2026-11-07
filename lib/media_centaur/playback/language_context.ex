defmodule MediaCentaur.Playback.LanguageContext do
  @moduledoc """
  The track policy of one playback session: the language preferences
  loaded for its entry (`init/1`, over the viewing's `Playback.Remembered`
  settings), the resolver's choice on each `track-list` and the subtitle
  enforcement it implies (`on_track_list/3`), and the track part of a
  viewer's settled settings (`capture/2`), which `Remembered` saves. Owns
  the policy read and answers `MpvSession` with the IPC to send; the
  session keeps the capture timer and sends. mpv's
  `track-list` is parsed into `TrackResolver.Track` structs by
  `MpvProperties`.

  The resolver is the source of truth: once subtitle tracks exist, mpv's
  `sid` is made to match its pick. Enforcement is driven from `track-list`
  updates only — a *viewer's* track switch fires `aid`/`sid`, never
  `track-list`, so it is never clobbered, and the session's own
  `set_property sid` echo lands on the capture path, not here — no loop.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Playback.{LanguagePolicy, MpvProperties, OverrideCapture, Remembered}
  alias MediaCentaur.Playback.{TrackResolver, Viewing}
  alias MediaCentaur.Playback.TrackResolver.Track

  defstruct [
    :policy,
    :override,
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
          override: Library.PlaybackOverride.t() | nil,
          original_language: String.t() | nil,
          priority_args: TrackResolver.priority_args(),
          resolver_choice: OverrideCapture.state() | nil,
          enforced_sid: term()
        }

  @doc """
  Build the language context for a playback session from its remembered
  settings: the global policy, with the profile's override and the
  title's original language when the viewing has an owner (ADR-078). An
  extra or an unattributed file has neither, and the policy alone applies.
  """
  @spec init(Remembered.t()) :: t()
  def init(%Remembered{override: override, original_language: original_language}) do
    policy = LanguagePolicy.load()

    %__MODULE__{
      policy: policy,
      override: override,
      original_language: original_language,
      priority_args: TrackResolver.priority_args(policy, override, original_language)
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
  The track fields to save for the viewer's settled selection: the
  divergence from the resolver's choice, or none when it matches — or
  before the resolver has chosen, when there is no baseline to compare.

  The selection is derived now, from the complete track lists — not from
  a snapshot taken when the `aid`/`sid` event fired: mpv auto-selects a
  sub from `slang` before subtitle tracks demux, so an event-time snapshot
  can read "no subs" while the eng sub is in fact selected. Deriving here
  is what stops the per-series `subtitles_off` poison — see
  `current_selection/4`.
  """
  @spec capture(t(), MpvProperties.t()) :: map()
  def capture(%__MODULE__{resolver_choice: nil}, %MpvProperties{}), do: %{}

  def capture(%__MODULE__{} = context, %MpvProperties{} = properties) do
    %MpvProperties{aid: aid, sid: sid, audio_tracks: audio_tracks, subtitle_tracks: subtitle_tracks} =
      properties

    selection = current_selection(aid, sid, audio_tracks, subtitle_tracks)

    case OverrideCapture.compute(context.resolver_choice, selection) do
      :no_change -> %{}
      {:override, attrs} -> attrs
    end
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
end
