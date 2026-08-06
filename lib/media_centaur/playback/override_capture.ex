defmodule MediaCentaur.Playback.OverrideCapture do
  @moduledoc """
  Pure diff function. Given what `TrackResolver.resolve/5` chose at
  episode start (`resolver_choice`) and what mpv is currently playing
  (`current_state`), computes the override row that captures the
  user's divergence from policy — or returns `:no_change` if the user
  hasn't actually diverged.

  Used by `MpvSession` whenever an `aid` or `sid` property-change
  event settles (post-debounce). The caller persists the result via
  `Library.MediaTrackOverrides.upsert/3` only when this returns
  `{:override, attrs}`; the `:no_change` case is a no-op (the
  override row, if it exists, is left alone — clearing it requires
  the explicit "Reset to default" UI action).

  ## Semantics

  The override row stores **divergence from policy**, not absolute
  state:

    * `audio_lang = nil`     → audio follows policy
    * `subtitle_lang = nil` + `subtitles_off = false` → subs follow policy
    * `subtitle_lang = nil` + `subtitles_off = true`  → subs explicitly disabled

  So a user who changes only audio (and doesn't touch subs) gets an
  override row with `audio_lang` set and the subtitle fields left at
  "follow policy."
  """

  @type state :: %{
          audio_lang: String.t() | nil,
          sub_lang: String.t() | nil,
          sub_forced: boolean()
        }

  @type override_attrs :: %{
          audio_lang: String.t() | nil,
          subtitle_lang: String.t() | nil,
          subtitle_forced: boolean(),
          subtitles_off: boolean()
        }

  @spec compute(state(), state()) :: {:override, override_attrs()} | :no_change
  def compute(resolver_choice, current_state) do
    attrs = %{
      audio_lang: audio_override(resolver_choice, current_state),
      subtitle_lang: subtitle_lang_override(resolver_choice, current_state),
      subtitle_forced: subtitle_forced_override(resolver_choice, current_state),
      subtitles_off: subtitles_off_override(resolver_choice, current_state)
    }

    if no_override?(attrs), do: :no_change, else: {:override, attrs}
  end

  defp audio_override(%{audio_lang: same}, %{audio_lang: same}), do: nil
  defp audio_override(_resolver, %{audio_lang: current}), do: current

  defp subtitle_lang_override(_resolver, %{sub_lang: nil}), do: nil

  defp subtitle_lang_override(%{sub_lang: same, sub_forced: same_forced}, %{
         sub_lang: same,
         sub_forced: same_forced
       }), do: nil

  defp subtitle_lang_override(_resolver, %{sub_lang: current}), do: current

  defp subtitle_forced_override(_resolver, %{sub_lang: nil}), do: false

  defp subtitle_forced_override(%{sub_lang: same, sub_forced: same_forced}, %{
         sub_lang: same,
         sub_forced: same_forced
       }), do: false

  defp subtitle_forced_override(_resolver, %{sub_forced: current}), do: current || false

  # subtitles_off captures the specific case "resolver wanted subs, user
  # turned them off." If resolver wanted nothing, the user picking nothing
  # isn't divergence (it's just "no subs, follow policy").
  defp subtitles_off_override(%{sub_lang: nil}, %{sub_lang: nil}), do: false
  defp subtitles_off_override(%{sub_lang: nil}, _current), do: false
  defp subtitles_off_override(_resolver, %{sub_lang: nil}), do: true
  defp subtitles_off_override(_resolver, _current), do: false

  defp no_override?(%{
         audio_lang: nil,
         subtitle_lang: nil,
         subtitle_forced: false,
         subtitles_off: false
       }), do: true

  defp no_override?(_), do: false
end
