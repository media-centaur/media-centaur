defmodule MediaCentaur.Playback.OverrideCapture do
  @moduledoc """
  Pure diff: the track settings a viewer changed. Given what was in effect
  (`baseline` — the resolver's choice, which already honours the title's
  remembered settings, or the last selection saved) and what mpv plays now
  (`selection`), returns the override fields to save — for the settings
  that changed, and only those.

  Audio and subtitles are separate settings: switching one never writes
  the other, so a remembered audio language survives a subtitle switch.
  A changed setting is saved as the viewer's explicit choice:

    * audio — `audio_lang`
    * subtitles — `subtitle_lang` with `subtitle_forced`, or
      `subtitles_off: true` when the viewer turned them off

  Going back to a title's default is never inferred from a selection; it
  is the menu's **Default** (`Playback.Remembered.use_default/3`).

  Used by `MpvSession` when an `aid` or `sid` change settles (after the
  capture debounce); `Playback.Remembered` saves the result.
  """

  @type state :: %{
          audio_lang: String.t() | nil,
          sub_lang: String.t() | nil,
          sub_forced: boolean()
        }

  @spec changes(state(), state()) :: map()
  def changes(baseline, selection),
    do: Map.merge(audio(baseline, selection), subtitles(baseline, selection))

  defp audio(%{audio_lang: same}, %{audio_lang: same}), do: %{}
  # A track without a language tag has nothing to remember it by.
  defp audio(_baseline, %{audio_lang: nil}), do: %{}
  defp audio(_baseline, %{audio_lang: lang}), do: %{audio_lang: lang}

  defp subtitles(%{sub_lang: lang, sub_forced: forced}, %{sub_lang: lang, sub_forced: forced}), do: %{}

  defp subtitles(_baseline, %{sub_lang: nil}),
    do: %{subtitle_lang: nil, subtitle_forced: false, subtitles_off: true}

  defp subtitles(_baseline, %{sub_lang: lang, sub_forced: forced}),
    do: %{subtitle_lang: lang, subtitle_forced: forced || false, subtitles_off: false}
end
