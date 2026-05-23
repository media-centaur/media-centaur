defmodule MediaCentaur.Playback.TrackResolver do
  @moduledoc """
  Pure track-selection oracle. Given the language policy, the
  per-entity override (if any), the file's audio + subtitle tracks, and
  the entity's original language, returns the indices of the audio and
  subtitle tracks the system should select.

  Two entry points:

    * `priority_args/3` — pre-launch: computes mpv launch flags
      (`--alang`, `--slang`, `--sub-visibility`) from policy + override
      alone. The file's track list isn't available yet.

    * `resolve/5` — post-launch: given the file's track list, picks
      exact track indices, honouring conditional sub logic, forced-sub
      fill_gaps, SDH preference, and override pinning. Used both for
      "what should mpv be playing right now?" and for "what did the
      policy expect?" when comparing user overrides during capture.

  See `MediaCentaur.Playback.LanguagePolicy` for the policy shape and
  `MediaCentaur.Library.MediaTrackOverride` for the override shape.
  """

  alias MediaCentaur.Library.MediaTrackOverride
  alias MediaCentaur.Playback.Iso639
  alias MediaCentaur.Playback.LanguagePolicy

  defmodule Track do
    @moduledoc """
    Representation of a single audio or subtitle track in a file. The
    caller (mpv `track-list` parser, ffprobe wrapper, factory) is
    responsible for extracting these fields.
    """
    @type t :: %__MODULE__{
            index: non_neg_integer(),
            lang: String.t() | nil,
            title: String.t() | nil,
            forced: boolean(),
            sdh: boolean()
          }
    defstruct [:index, :lang, :title, forced: false, sdh: false]
  end

  @type resolution :: %{
          audio_index: non_neg_integer() | nil,
          audio_lang: String.t() | nil,
          sub_index: non_neg_integer() | nil,
          sub_lang: String.t() | nil,
          sub_forced: boolean(),
          decision_log: [String.t()]
        }

  @type priority_args :: %{
          alang: [String.t()],
          slang: [String.t()],
          sub_visibility: boolean(),
          subs_match_audio: String.t(),
          disable_subs: boolean()
        }

  # ---------------------------------------------------------------------------
  # priority_args/3 — pre-launch
  # ---------------------------------------------------------------------------

  @spec priority_args(LanguagePolicy.t(), MediaTrackOverride.t() | nil, String.t() | nil) ::
          priority_args()
  def priority_args(%LanguagePolicy{} = policy, override, original_language) do
    %{
      alang: build_alang(policy, override, original_language),
      slang: build_slang(policy, override),
      sub_visibility: build_sub_visibility(policy, override),
      subs_match_audio: build_subs_match_audio(policy, override),
      disable_subs: build_disable_subs(policy, override)
    }
  end

  defp build_alang(policy, override, original_language) do
    override_prefix =
      case override do
        %{audio_lang: lang} when is_binary(lang) -> [lang]
        _ -> []
      end

    policy_priorities =
      Enum.flat_map(policy.audio_priority, fn
        "original" when is_binary(original_language) -> [original_language]
        "understood" -> policy.understood_languages
        _ -> []
      end)

    Enum.uniq(override_prefix ++ policy_priorities)
  end

  defp build_slang(policy, override) do
    cond do
      override_subtitles_off?(override) ->
        []

      override_subtitle_lang(override) != nil ->
        Enum.uniq([override_subtitle_lang(override) | policy.understood_languages])

      policy.subtitles_when == "off" ->
        []

      true ->
        policy.understood_languages
    end
  end

  defp build_sub_visibility(policy, override) do
    cond do
      override_subtitles_off?(override) -> false
      policy.subtitles_when == "off" -> false
      true -> true
    end
  end

  # mpv's `--subs-with-matching-audio=<yes|forced|no>` controls
  # auto-selection of a sub whose language matches the audio:
  #
  #   * "yes"    — always autoselect (used for `always` + explicit overrides)
  #   * "no"     — never autoselect when audio matches the sub language
  #                (used for plain `when_audio_not_understood`)
  #   * "forced" — when audio matches, autoselect only a *forced* sub;
  #                when audio doesn't match, autoselect a normal sub.
  #                This is exactly the `fill_gaps` rule — full subs for
  #                foreign audio, forced-only ("Greedo scene") subs when
  #                the audio is in a language you understand.
  defp build_subs_match_audio(policy, override) do
    cond do
      override_subtitle_lang(override) != nil ->
        "yes"

      policy.subtitles_when == "always" ->
        "yes"

      policy.subtitles_when == "when_audio_not_understood" and policy.forced_subs == "fill_gaps" ->
        "forced"

      true ->
        "no"
    end
  end

  defp build_disable_subs(policy, override) do
    cond do
      override_subtitles_off?(override) -> true
      override_subtitle_lang(override) != nil -> false
      policy.subtitles_when == "off" -> true
      true -> false
    end
  end

  # ---------------------------------------------------------------------------
  # resolve/5 — full post-launch resolution
  # ---------------------------------------------------------------------------

  @spec resolve(
          LanguagePolicy.t(),
          MediaTrackOverride.t() | nil,
          [Track.t()],
          [Track.t()],
          String.t() | nil
        ) :: resolution()
  def resolve(%LanguagePolicy{} = policy, override, audio_tracks, subtitle_tracks, original_language)
      when is_list(audio_tracks) and is_list(subtitle_tracks) do
    {audio_track, audio_log} = pick_audio(policy, override, audio_tracks, original_language)
    audio_lang = audio_track && audio_track.lang

    {sub_track, sub_log} = pick_subtitle(policy, override, subtitle_tracks, audio_lang)

    %{
      audio_index: audio_track && audio_track.index,
      audio_lang: audio_lang,
      sub_index: sub_track && sub_track.index,
      sub_lang: sub_track && sub_track.lang,
      sub_forced: (sub_track && sub_track.forced) || false,
      decision_log: audio_log ++ sub_log
    }
  end

  # ---------------------------------------------------------------------------
  # Audio
  # ---------------------------------------------------------------------------

  defp pick_audio(policy, override, tracks, original_language) do
    case override do
      %{audio_lang: lang} when is_binary(lang) ->
        case find_by_lang(tracks, lang) do
          nil ->
            {track, log} = pick_audio_from_policy(policy, tracks, original_language)
            {track, ["audio: override lang=#{lang} not in file, falling back to policy" | log]}

          track ->
            {track, ["audio: override lang=#{lang} → index #{track.index}"]}
        end

      _ ->
        pick_audio_from_policy(policy, tracks, original_language)
    end
  end

  defp pick_audio_from_policy(policy, tracks, original_language) do
    walk_audio_priority(policy.audio_priority, tracks, original_language, policy.understood_languages)
  end

  defp walk_audio_priority([], _tracks, _original, _understood) do
    {nil, ["audio: no track matched any priority"]}
  end

  defp walk_audio_priority([category | rest], tracks, original, understood) do
    case pick_audio_category(category, tracks, original, understood) do
      nil ->
        walk_audio_priority(rest, tracks, original, understood)

      track ->
        {track, ["audio: priority=#{category} matched lang=#{track.lang || "?"} index=#{track.index}"]}
    end
  end

  defp pick_audio_category("original", tracks, original, _understood) when is_binary(original) do
    find_by_lang(tracks, original)
  end

  defp pick_audio_category("original", _tracks, _original, _understood), do: nil

  defp pick_audio_category("understood", tracks, _original, understood) do
    Enum.find_value(understood, fn lang -> find_by_lang(tracks, lang) end)
  end

  defp pick_audio_category("any", tracks, _original, _understood) do
    List.first(tracks)
  end

  defp pick_audio_category(_, _, _, _), do: nil

  defp find_by_lang(tracks, lang) do
    Enum.find(tracks, &matches_lang?(&1, lang))
  end

  # ---------------------------------------------------------------------------
  # Subtitles
  # ---------------------------------------------------------------------------

  defp pick_subtitle(policy, override, tracks, audio_lang) do
    cond do
      override_subtitles_off?(override) ->
        {nil, ["subs: override subtitles_off=true → disabled"]}

      override_subtitle_lang(override) != nil ->
        pick_override_subtitle(override, tracks, policy, audio_lang)

      true ->
        pick_subtitle_from_policy(policy, tracks, audio_lang)
    end
  end

  defp pick_override_subtitle(override, tracks, policy, audio_lang) do
    lang = override.subtitle_lang
    forced = override.subtitle_forced || false

    case find_sub_in_lang(tracks, lang, forced) do
      nil ->
        {track, log} = pick_subtitle_from_policy(policy, tracks, audio_lang)

        {track,
         [
           "subs: override lang=#{lang}#{if forced, do: " forced", else: ""} not in file, falling back to policy"
           | log
         ]}

      track ->
        {track, ["subs: override lang=#{lang} → index #{track.index}"]}
    end
  end

  defp pick_subtitle_from_policy(policy, tracks, audio_lang) do
    cond do
      policy.subtitles_when == "off" ->
        case forced_fallback(policy, tracks, audio_lang) do
          nil -> {nil, ["subs: policy=off → no subs"]}
          track -> {track, ["subs: policy=off, forced fallback → index #{track.index}"]}
        end

      policy.subtitles_when == "when_audio_not_understood" and
          audio_understood?(audio_lang, policy.understood_languages) ->
        case forced_fallback(policy, tracks, audio_lang) do
          nil ->
            {nil, ["subs: audio is understood (lang=#{audio_lang}), no subs"]}

          track ->
            {track,
             ["subs: audio is understood (lang=#{audio_lang}), forced fallback → index #{track.index}"]}
        end

      true ->
        case pick_main_subtitle(policy, tracks, audio_lang) do
          nil ->
            case forced_fallback(policy, tracks, audio_lang) do
              nil ->
                {nil, ["subs: no main sub found and no forced fallback"]}

              track ->
                {track, ["subs: no main sub found, forced fallback → index #{track.index}"]}
            end

          track ->
            {track, ["subs: main sub picked lang=#{track.lang || "?"} index=#{track.index}"]}
        end
    end
  end

  defp pick_main_subtitle(policy, tracks, audio_lang) do
    target_langs = subtitle_target_langs(policy, audio_lang)

    Enum.find_value(target_langs, fn lang ->
      candidates = Enum.filter(tracks, &(matches_lang?(&1, lang) and not &1.forced))

      case policy.subtitles_variant do
        "sdh_preferred" -> Enum.find(candidates, & &1.sdh) || List.first(candidates)
        _ -> List.first(candidates)
      end
    end)
  end

  defp subtitle_target_langs(%{subtitles_language: "audio_language"}, audio_lang)
       when is_binary(audio_lang), do: [audio_lang]

  defp subtitle_target_langs(%{subtitles_language: "audio_language"}, _audio_lang), do: []

  defp subtitle_target_langs(%{understood_languages: languages}, _audio_lang), do: languages

  defp forced_fallback(%{forced_subs: "never"}, _tracks, _audio_lang), do: nil

  defp forced_fallback(%{forced_subs: "always"}, tracks, audio_lang) do
    find_forced(tracks, audio_lang)
  end

  defp forced_fallback(%{forced_subs: "fill_gaps"} = policy, tracks, audio_lang) do
    if audio_understood?(audio_lang, policy.understood_languages) do
      find_forced(tracks, audio_lang)
    end
  end

  defp forced_fallback(_policy, _tracks, _audio_lang), do: nil

  defp find_forced(_tracks, nil), do: nil

  defp find_forced(tracks, lang) do
    Enum.find(tracks, &(matches_lang?(&1, lang) and &1.forced))
  end

  defp find_sub_in_lang(tracks, lang, forced) do
    candidates = Enum.filter(tracks, &matches_lang?(&1, lang))
    Enum.find(candidates, fn track -> track.forced == forced end) || List.first(candidates)
  end

  defp audio_understood?(nil, _understood), do: false
  defp audio_understood?(lang, understood), do: Iso639.find_match(lang, understood) != nil

  # Single source of truth for "does this track's language match the
  # requested code?". Every language comparison in the resolver routes
  # through here — see ADR on canonical language codes. Inputs are
  # already canonicalized at the boundary (LanguageContext.parse_track_list,
  # LanguagePolicy.load), so `Iso639.equal?/2` is belt-and-suspenders:
  # it would still match even if a raw code slipped past the boundary.
  defp matches_lang?(track, lang), do: Iso639.equal?(track.lang, lang)

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  defp override_subtitles_off?(%{subtitles_off: true}), do: true
  defp override_subtitles_off?(_), do: false

  defp override_subtitle_lang(%{subtitle_lang: lang}) when is_binary(lang), do: lang
  defp override_subtitle_lang(_), do: nil
end
